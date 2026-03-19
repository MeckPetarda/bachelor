import { type Component } from "solid-js";
import styles from "./Toggle.module.css";

interface Props {
  checked: boolean;
  onChange: (value: boolean) => void;
  label?: string;
  id?: string;
}

export const Toggle: Component<Props> = (props) => {
  const id = props.id ?? "toggle";

  return (
    <label class={styles.wrapper} for={id}>
      <input
        id={id}
        type="checkbox"
        class={styles.input}
        checked={props.checked}
        onChange={(e) => props.onChange(e.currentTarget.checked)}
      />
      <span class={styles.track}>
        <span class={styles.thumb} />
      </span>
      {props.label && <span class={styles.label}>{props.label}</span>}
    </label>
  );
};
