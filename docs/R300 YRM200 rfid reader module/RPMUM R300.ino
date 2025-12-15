/*
由深圳远诺德有限公司编写
复制及使用请保留版权所属
*/


/*多次读取指令*/
//unsigned  char ReadMulti[10] = {0XBB,0X00,0X27,0X00,0X03,0X22,0XFF,0XFF,0X4A,0X7E};
//  READ CARD  :A0 06 01 8B 00 00 01 CD
// 定义发送的指令数组
unsigned char ReadMulti[8] = {0XA0, 0X06, 0X01, 0X8B, 0X00, 0X00, 0X01, 0XCD};
// 用于记录时间的变量，单位秒
unsigned int timeSec = 0;
// 用于记录时间的变量，单位分钟
unsigned int timemin = 0;
// 用于记录接收到数据的位置索引
unsigned int dataAdd = 0;
// 用于临时存储从串口读取到的单个字节数据
unsigned int incomedate = 0;
// 指令代码相关状态标志
unsigned int parState = 0;
// 指令参数相关状态标志
unsigned int codeState = 0;

void setup() 
{
    // 设置串口，并设置LED引脚为输出模式
    pinMode(LED_BUILTIN, OUTPUT);
    Serial.begin(115200); // 设置串口波特率为115200
    Serial.println("Hello world.");
    Serial.write(ReadMulti, 8);  // 发送8个字节的指令，与指令数组长度匹配
}

void loop() 
{
    // 间隔一段时间后发送循环读取命令
    timeSec++;
    if (timeSec >= 50000) {
        timemin++;
        timeSec = 0;
        if (timemin >= 20) {
            timemin = 0;
            // 发送循环读取指令，点亮LED指示发送操作
            digitalWrite(LED_BUILTIN, HIGH);
            Serial.write(ReadMulti, 8);
            digitalWrite(LED_BUILTIN, LOW); 
        }
    }

    if (Serial.available() > 0)  // 串口接收到数据
    {
        incomedate = Serial.read();  // 获取串口接收到的数据

        // 判断是否为对应指令代码（这里假设新指令代码所在字节位置和值有变化，按实际情况改）
        if ((incomedate == 0x10) && (parState == 0))  // 假设指令代码变为0x10，按实际调整
        {
            parState = 1;
        }
        // 判断是否为对应指令参数（假设新指令参数所在字节位置和值有变化，按实际情况改）
        else if ((parState == 1) && (incomedate == 0x33) && (codeState == 0))  // 假设指令参数变为0x33，按实际调整
        {
            codeState = 1;
            dataAdd = 5;  // 根据新指令回复格式调整此处起始处理数据的位置（假设情况）
        }
        else if (codeState == 1)
        {
            dataAdd++;
            // 获取RSSI（这里假设RSSI位置等没变化，如果有变化按实际改）
            if (dataAdd == 6)
            {
                Serial.print("RSSI:");
                Serial.println(incomedate, HEX);
            }
            // 获取PC码（同样假设位置等没变化，有变化按实际改）
            else if ((dataAdd == 7) || (dataAdd == 8))
            {
                if (dataAdd == 7)
                {
                    Serial.print("PC:");
                    Serial.print(incomedate, HEX);
                }
                else
                {
                    Serial.println(incomedate, HEX);
                }
            }
            // 获取EPC（假设位置范围等没变化，按实际改）
            else if ((dataAdd >= 9) && (dataAdd <= 20))
            {
                if (dataAdd == 9)
                {
                    Serial.print("EPC:");
                }
                Serial.print(incomedate, HEX);
            }
            // 位置溢出，进行重新接收
            else if (dataAdd >= 21)
            {
                Serial.println(" ");
                dataAdd = 0;
                parState = 0;
                codeState = 0;
            }
        }
        else
        {
            dataAdd = 0;
            parState = 0;
            codeState = 0;
        }
    }
}