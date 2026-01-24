/**
 * @file dns_server.c
 * @brief DNS Server Implementation for Captive Portal
 *
 * Implements a simple DNS server that responds to all queries with the AP's
 * IP address (192.168.4.1) to enable captive portal detection.
 *
 * DNS Protocol Overview (simplified for captive portal):
 * - DNS uses UDP port 53
 * - Query packet contains: ID (2 bytes) + Flags + Question
 * - Response packet contains: same ID + Response flags + Question + Answer
 * - We respond to ANY query with the same IP (192.168.4.1)
 */

#include "dns_server.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"

#include <string.h>

static const char *TAG = "DNS_SERVER";

/* DNS Server Configuration */
#define DNS_PORT            53
#define DNS_MAX_PACKET_SIZE 512
#define DNS_TASK_STACK_SIZE 4096
#define DNS_TASK_PRIORITY   5
#define DNS_TASK_NAME       "dns_server"

/* AP IP Address: 192.168.4.1 */
#define AP_IP_BYTE_0 192
#define AP_IP_BYTE_1 168
#define AP_IP_BYTE_2 4
#define AP_IP_BYTE_3 1

/* DNS Header Offsets */
#define DNS_HEADER_SIZE     12
#define DNS_ID_OFFSET       0
#define DNS_FLAGS_OFFSET    2
#define DNS_QDCOUNT_OFFSET  4
#define DNS_ANCOUNT_OFFSET  6
#define DNS_NSCOUNT_OFFSET  8
#define DNS_ARCOUNT_OFFSET  10

/* DNS Response Flags
 * Bit 15: QR (1 = response)
 * Bits 11-14: OPCODE (0 = standard query)
 * Bit 10: AA (1 = authoritative answer)
 * Bit 9: TC (0 = not truncated)
 * Bit 8: RD (copy from query - recursion desired)
 * Bit 7: RA (0 = recursion not available)
 * Bits 4-6: Z (reserved, must be 0)
 * Bits 0-3: RCODE (0 = no error)
 */
#define DNS_FLAG_QR         0x8000  /* Response flag */
#define DNS_FLAG_AA         0x0400  /* Authoritative answer */

/* DNS Record Types */
#define DNS_TYPE_A          0x0001  /* IPv4 address */
#define DNS_CLASS_IN        0x0001  /* Internet class */

/* DNS Answer TTL (seconds) */
#define DNS_TTL             60

/* Module State */
static int dns_socket = -1;
static TaskHandle_t dns_task_handle = NULL;
static volatile bool dns_running = false;

/**
 * @brief Build a DNS response packet
 *
 * Takes the original query packet and builds a response that includes:
 * - Same transaction ID as the query
 * - Response flags (QR=1, AA=1)
 * - Original question section
 * - Answer section with A record pointing to 192.168.4.1
 *
 * @param query         Original DNS query packet
 * @param query_len     Length of query packet
 * @param response      Buffer to write response (must be at least query_len + 16 bytes)
 * @return              Length of response packet
 */
static size_t build_dns_response(const uint8_t *query, size_t query_len, uint8_t *response)
{
    if (query_len < DNS_HEADER_SIZE) {
        return 0;
    }

    /* Copy the original query to response (includes header + question) */
    memcpy(response, query, query_len);

    /* Get original flags and set response bits */
    uint16_t flags = (query[DNS_FLAGS_OFFSET] << 8) | query[DNS_FLAGS_OFFSET + 1];
    flags |= DNS_FLAG_QR;   /* Set response flag */
    flags |= DNS_FLAG_AA;   /* Set authoritative answer flag */

    /* Write response flags */
    response[DNS_FLAGS_OFFSET] = (flags >> 8) & 0xFF;
    response[DNS_FLAGS_OFFSET + 1] = flags & 0xFF;

    /* Set answer count to 1 */
    response[DNS_ANCOUNT_OFFSET] = 0;
    response[DNS_ANCOUNT_OFFSET + 1] = 1;

    /* Build answer section after the question
     * Answer format:
     *   Name: pointer to question name (0xC00C = offset 12)
     *   Type: A (2 bytes)
     *   Class: IN (2 bytes)
     *   TTL: (4 bytes)
     *   RDLength: 4 (2 bytes - length of IPv4 address)
     *   RData: IPv4 address (4 bytes)
     */
    size_t answer_offset = query_len;

    /* Name pointer (0xC00C points to offset 12, the question name) */
    response[answer_offset++] = 0xC0;
    response[answer_offset++] = 0x0C;

    /* Type A (IPv4 address) */
    response[answer_offset++] = (DNS_TYPE_A >> 8) & 0xFF;
    response[answer_offset++] = DNS_TYPE_A & 0xFF;

    /* Class IN (Internet) */
    response[answer_offset++] = (DNS_CLASS_IN >> 8) & 0xFF;
    response[answer_offset++] = DNS_CLASS_IN & 0xFF;

    /* TTL (4 bytes, big-endian) */
    response[answer_offset++] = (DNS_TTL >> 24) & 0xFF;
    response[answer_offset++] = (DNS_TTL >> 16) & 0xFF;
    response[answer_offset++] = (DNS_TTL >> 8) & 0xFF;
    response[answer_offset++] = DNS_TTL & 0xFF;

    /* RDLength (2 bytes) - IPv4 is 4 bytes */
    response[answer_offset++] = 0;
    response[answer_offset++] = 4;

    /* RData - IP address 192.168.4.1 */
    response[answer_offset++] = AP_IP_BYTE_0;
    response[answer_offset++] = AP_IP_BYTE_1;
    response[answer_offset++] = AP_IP_BYTE_2;
    response[answer_offset++] = AP_IP_BYTE_3;

    return answer_offset;
}

/**
 * @brief DNS server task
 *
 * Continuously listens for DNS queries on UDP port 53 and responds
 * to all queries with the AP's IP address (192.168.4.1).
 *
 * @param pvParameters  Not used
 */
static void dns_server_task(void *pvParameters)
{
    uint8_t rx_buffer[DNS_MAX_PACKET_SIZE];
    uint8_t tx_buffer[DNS_MAX_PACKET_SIZE + 16];  /* Extra space for answer */
    struct sockaddr_in client_addr;
    socklen_t client_addr_len;
    int recv_len;

    ESP_LOGI(TAG, "DNS server task started");

    while (dns_running) {
        client_addr_len = sizeof(client_addr);

        /* Wait for incoming DNS query */
        recv_len = recvfrom(dns_socket, rx_buffer, sizeof(rx_buffer), 0,
                           (struct sockaddr *)&client_addr, &client_addr_len);

        if (recv_len < 0) {
            if (dns_running) {
                /* Only log if we're still supposed to be running */
                ESP_LOGW(TAG, "recvfrom failed: errno %d", errno);
            }
            continue;
        }

        if (recv_len < DNS_HEADER_SIZE) {
            ESP_LOGW(TAG, "Received packet too small (%d bytes)", recv_len);
            continue;
        }

        /* Log the query (for debugging) */
        ESP_LOGD(TAG, "DNS query from %d.%d.%d.%d",
                (client_addr.sin_addr.s_addr >> 0) & 0xFF,
                (client_addr.sin_addr.s_addr >> 8) & 0xFF,
                (client_addr.sin_addr.s_addr >> 16) & 0xFF,
                (client_addr.sin_addr.s_addr >> 24) & 0xFF);

        /* Build response */
        size_t response_len = build_dns_response(rx_buffer, recv_len, tx_buffer);
        if (response_len == 0) {
            ESP_LOGW(TAG, "Failed to build DNS response");
            continue;
        }

        /* Send response back to client */
        int sent = sendto(dns_socket, tx_buffer, response_len, 0,
                         (struct sockaddr *)&client_addr, client_addr_len);

        if (sent < 0) {
            ESP_LOGW(TAG, "sendto failed: errno %d", errno);
        } else {
            ESP_LOGD(TAG, "Sent DNS response (%d bytes) with IP %d.%d.%d.%d",
                    sent, AP_IP_BYTE_0, AP_IP_BYTE_1, AP_IP_BYTE_2, AP_IP_BYTE_3);
        }
    }

    ESP_LOGI(TAG, "DNS server task stopping");
    vTaskDelete(NULL);
}

esp_err_t dns_server_start(void)
{
    if (dns_running) {
        ESP_LOGW(TAG, "DNS server already running");
        return ESP_ERR_INVALID_STATE;
    }

    /* Create UDP socket */
    dns_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (dns_socket < 0) {
        ESP_LOGE(TAG, "Failed to create socket: errno %d", errno);
        return ESP_FAIL;
    }

    /* Allow socket reuse for quick restart */
    int opt = 1;
    setsockopt(dns_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    /* Bind to port 53 on all interfaces */
    struct sockaddr_in server_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(DNS_PORT),
        .sin_addr.s_addr = htonl(INADDR_ANY)
    };

    if (bind(dns_socket, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        ESP_LOGE(TAG, "Failed to bind socket to port %d: errno %d", DNS_PORT, errno);
        close(dns_socket);
        dns_socket = -1;
        return ESP_FAIL;
    }

    /* Start DNS handler task */
    dns_running = true;

    BaseType_t ret = xTaskCreate(
        dns_server_task,
        DNS_TASK_NAME,
        DNS_TASK_STACK_SIZE,
        NULL,
        DNS_TASK_PRIORITY,
        &dns_task_handle
    );

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create DNS server task");
        dns_running = false;
        close(dns_socket);
        dns_socket = -1;
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "DNS server started on port %d", DNS_PORT);
    return ESP_OK;
}

esp_err_t dns_server_stop(void)
{
    if (!dns_running) {
        ESP_LOGD(TAG, "DNS server not running");
        return ESP_ERR_INVALID_STATE;
    }

    /* Signal task to stop */
    dns_running = false;

    /* Close socket to unblock recvfrom */
    if (dns_socket >= 0) {
        shutdown(dns_socket, SHUT_RDWR);
        close(dns_socket);
        dns_socket = -1;
    }

    /* Give task time to clean up */
    if (dns_task_handle != NULL) {
        /* Wait a bit for task to exit gracefully */
        vTaskDelay(pdMS_TO_TICKS(100));
        dns_task_handle = NULL;
    }

    ESP_LOGI(TAG, "DNS server stopped");
    return ESP_OK;
}

bool dns_server_is_running(void)
{
    return dns_running;
}
