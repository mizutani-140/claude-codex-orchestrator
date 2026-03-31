import { describe, expect, it } from "vitest";

import { parseMarkdown, serializeMarkdown } from "../src/parser.js";
import type { Task } from "../src/types.js";

describe("parseMarkdown", () => {
  it("returns an empty array for empty content", () => {
    expect(parseMarkdown("")).toEqual([]);
  });

  it("parses an incomplete task", () => {
    expect(parseMarkdown("- [ ] Buy milk")).toEqual([{ text: "Buy milk", done: false }]);
  });

  it("parses a completed task", () => {
    expect(parseMarkdown("- [x] Done")).toEqual([{ text: "Done", done: true }]);
  });

  it("parses multiple task lines", () => {
    expect(parseMarkdown("- [ ] Buy milk\n- [X] Call mom")).toEqual([
      { text: "Buy milk", done: false },
      { text: "Call mom", done: true }
    ]);
  });

  it("ignores non-task lines", () => {
    expect(parseMarkdown("# Title\n\n- [ ] Buy milk\nplain text")).toEqual([
      { text: "Buy milk", done: false }
    ]);
  });
});

describe("serializeMarkdown", () => {
  it("round-trips through the parser", () => {
    const tasks: Task[] = [
      { text: "Buy milk", done: false },
      { text: "Call mom", done: true }
    ];

    expect(parseMarkdown(serializeMarkdown(tasks))).toEqual(tasks);
  });

  it("serializes done and not-done tasks in the expected format", () => {
    expect(serializeMarkdown([{ text: "Buy milk", done: false }])).toBe("- [ ] Buy milk\n");
    expect(serializeMarkdown([{ text: "Done", done: true }])).toBe("- [x] Done\n");
  });
});
