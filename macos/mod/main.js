import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { checking, closeOverlay, exec, props, theme } from "herdr";
import { ago, filterAi, matchItem, resumeCommand } from "./model.js";
import { NODE, TOOL } from "./config.js";

const providers = { all: "전체", claude: "Claude", codex: "Codex" };

export default class ConversationPicker extends View {
  init(_props, cx) {
    this.rows = [];
    this.ai = "all";
    this.query = "";
    this.loading = false;
    this.running = false;
    this.status = "";
    this.input = InputState.new({ placeholder: "대화 제목, 작업 폴더, 세션 ID 검색" });
    this.input.on("change", (_event, context) => {
      this.query = this.input.value().trim().toLowerCase();
      context.notify();
    });

    if (checking()) return;
    this.input.focus();
    this.refresh(cx);
  }

  dismiss() {
    closeOverlay(props().overlay);
  }

  refresh(cx) {
    if (this.loading || this.running) return;
    this.loading = true;
    this.status = "";
    cx.notify();

    cx.spawn(async (context) => {
      try {
        const result = await exec(NODE, [TOOL, "json", "--all", "--days", "60", "--limit", "200"]);
        if (result.code !== 0) throw new Error(result.stderr.trim() || "대화 목록을 읽지 못했습니다.");
        const rows = JSON.parse(result.stdout);
        if (!Array.isArray(rows)) throw new Error("대화 목록 응답을 읽지 못했습니다.");
        const cutoff = Date.now() - 60 * 86400000;
        this.rows = rows.filter((row) => row.live || row.mtimeMs >= cutoff).map((row) => ({
          ...row,
          fullId: row.sid,
          idShort: row.short,
          where: row.cwd || row.folder,
          text: row.lastPrompt || "",
        }));
        this.status = result.stderr.trim();
      } catch (error) {
        this.status = String(error.message || error).slice(0, 240);
      } finally {
        this.loading = false;
        context.notify();
      }
    });
  }

  open(row, cx) {
    if (this.running || this.loading || row.matchUncertain || row.missing || !resumeCommand(row)) return;
    this.running = true;
    this.status = row.live ? "열린 탭을 확인하는 중…" : "대화를 확인하는 중…";
    cx.notify();
    cx.spawn(async (context) => {
      try {
        const result = await exec(NODE, [TOOL, "open", row.fullId, "--json"]);
        const response = result.stdout ? JSON.parse(result.stdout) : {};
        if (result.code === 0 && response.ok) {
          this.dismiss();
          return;
        }
        this.status = response.message || result.stderr.trim() || "대화를 열지 못했습니다.";
      } catch (error) {
        this.status = String(error.message || error).slice(0, 240);
      } finally {
        this.running = false;
        context.notify();
      }
    });
  }

  copy(row, cx) {
    const command = resumeCommand(row);
    if (!command) return;
    try {
      cx.write_to_clipboard(command);
      this.status = "재개 명령을 복사했습니다. 원래 작업 폴더의 터미널에서 실행하세요.";
    } catch {
      this.status = "재개 명령을 복사하지 못했습니다.";
    }
    cx.notify();
  }

  render() {
    const t = theme();
    const button = (id, label, action, { selected = false, disabled = false } = {}) => {
      const element = h_flex().id(id).flex_none().items_center().h(28).px(9).rounded(6)
        .bg(selected ? t.selected : t.raised).border_1().border_color(t.border)
        .text_size(12).text_color(t.foreground).child(label);
      if (disabled) return element.opacity(0.45).cursor_not_allowed();
      return element.cursor_pointer().hover((el) => el.bg(t.hover)).on_click(action);
    };
    const text = (size, value, color = t.foreground) => div().text_size(size).text_color(color).child(value);
    const rows = filterAi(this.rows, this.ai).filter((row) => matchItem(row, this.query));
    const rowElements = rows.map((row, index) => {
      const key = `conversation-${index}-${row.fullId}`;
      let state = row.live ? "열린 탭" : "";
      if (row.matchUncertain) state = "실행 중인 대화인지 확인 필요";
      if (row.missing) state = "대화 기록 없음";
      const time = Number.isFinite(row.mtimeMs) && row.mtimeMs > 0 ? ago(row.mtimeMs) : "시각 확인 불가";
      const canResume = !!resumeCommand(row);

      return h_flex().id(key).items_center().gap(8).px(10).py(8).border_b_1().border_color(t.border)
        .child(v_flex().flex_1().min_w(0).gap(3)
          .child(text(13, row.title || row.folder || row.idShort || "제목 없음").font_semibold().truncate())
          .child(text(11, [row.ai, row.where, time, state].filter(Boolean).join(" · "), t.muted).truncate()))
        .when(canResume, (el) => el.child(button(`${key}-copy`, "명령 복사", (_event, cx) => this.copy(row, cx))))
        .when(canResume && !row.matchUncertain && !row.missing, (el) => el.child(button(
          `${key}-open`, row.live ? "탭으로 이동" : "이어 열기",
          (_event, cx) => this.open(row, cx), { disabled: this.running || this.loading },
        )));
    });
    const empty = this.loading ? "대화를 불러오는 중…" : this.query ? "검색어와 일치하는 대화가 없습니다." : "최근 60일 동안 찾은 대화가 없습니다.";

    return v_flex().id("conversation-picker").size_full().gap(10).p(14).bg(t.popover)
      .on_key_down((event, cx) => {
        if (event.key === "escape") {
          this.dismiss();
          cx.stop_propagation();
        }
      })
      .child(h_flex().gap(8).items_center()
        .child(image("mods/sodam-conversation-picker/icon.png").w(36).h(36).flex_none())
        .child(text(17, "대화냥줍").font_semibold().flex_none())
        .child(text(11, "Forked from SoDam Herdr Session Keeper", t.muted).truncate())
        .child(h_flex().flex_1().min_w(0).h(32).px(10).rounded(6).border_1().border_color(t.border)
          .child(Input.new(this.input).size_full().text_size(13).text_color(t.foreground)))
        .child(button("conversation-refresh", "새로고침", (_event, cx) => this.refresh(cx), { disabled: this.loading || this.running }))
        .child(button("conversation-close", "닫기", () => this.dismiss())))
      .child(h_flex().gap(6).items_center()
        .children(Object.entries(providers).map(([key, label]) => button(`conversation-ai-${key}`, label, (_event, cx) => {
          this.ai = key;
          cx.notify();
        }, { selected: key === this.ai })))
        .child(text(12, `${rows.length}개`, t.muted)))
      .child(v_flex().id("conversation-list").flex_1().min_h(0).overflow_y_scrollbar()
        .children(rowElements)
        .when(rows.length === 0, (el) => el.child(text(13, empty, t.muted).p(12))))
      .when(!!this.status, (el) => el.child(text(12, this.status, t.muted).px(8).py(5)));
  }
}
