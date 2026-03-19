import { type Component, onMount, onCleanup, type JSX } from "solid-js";
import { A } from "@solidjs/router";
import { Toast } from "./components/Toast";
import { connect, disconnect } from "./stores/websocket";
import styles from "./App.module.css";

interface AppProps {
  children?: JSX.Element;
}

const App: Component<AppProps> = (props) => {
  onMount(() => {
    connect();
  });

  onCleanup(() => {
    disconnect();
  });

  return (
    <div class={styles.app}>
      <nav class={styles.nav}>
        <div class={styles.navBrand}>Lighthouse Dashboard</div>
        <div class={styles.navLinks}>
          <A href="/" class={styles.navLink} activeClass={styles.active} end>
            Lighthouses
          </A>
          <A href="/groups" class={styles.navLink} activeClass={styles.active}>
            Groups
          </A>
          <A href="/events" class={styles.navLink} activeClass={styles.active}>
            Events
          </A>
          <A href="/users" class={styles.navLink} activeClass={styles.active}>
            Users
          </A>
        </div>
      </nav>
      <main class={styles.main}>{props.children}</main>
      <Toast />
    </div>
  );
};

export default App;
