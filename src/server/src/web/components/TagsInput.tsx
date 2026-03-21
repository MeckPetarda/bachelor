import { type Component, For, createSignal } from "solid-js";
import styles from "./TagsInput.module.css";

interface Props {
  value: string[];
  onChange: (tags: string[]) => void;
}

export const TagsInput: Component<Props> = (props) => {
  const [draft, setDraft] = createSignal("");

  const commitDraft = () => {
    const trimmed = draft().trim();
    if (!trimmed) return;
    props.onChange([...props.value, trimmed]);
    setDraft("");
  };

  const updateTag = (index: number, value: string) => {
    const updated = [...props.value];
    updated[index] = value;
    props.onChange(updated);
  };

  const removeTag = (index: number) => {
    props.onChange(props.value.filter((_, i) => i !== index));
  };

  return (
    <div class={styles.container}>
      <For each={props.value}>
        {(tag, i) => (
          <div class={styles.tagRow}>
            <span class={styles.tagDot} />
            <input
              type="text"
              class={`input ${styles.tagInput}`}
              value={tag}
              onInput={(e) => updateTag(i(), e.currentTarget.value)}
            />
            <button
              type="button"
              class={styles.removeBtn}
              onClick={() => removeTag(i())}
              title="Remove tag"
            >
              *
            </button>
          </div>
        )}
      </For>

      {/* New-tag row - + is decorative, entry is committed when the field loses focus */}
      <div class={styles.tagRow}>
        <span class={`${styles.tagDot} ${styles.tagDotAdd}`} />
        <input
          type="text"
          class={`input ${styles.tagInput}`}
          value={draft()}
          onInput={(e) => setDraft(e.currentTarget.value)}
          onBlur={commitDraft}
          placeholder="Add EPC string..."
        />
        <span class={`${styles.removeBtn} ${styles.addIcon}`}>+</span>
      </div>
    </div>
  );
};
