from pathlib import Path
import re

import pytest


MT5_SOURCE = Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5"
MT4_SOURCE = Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT4.mq4"

from strategy_logic import (
    CycleMode, Direction, DistanceMode, ExecutionOwnershipRegistry,
    ExposureSnapshot, GuiStateModel, OrderType, ParallelStrategyModel, PendingRecord,
    PreparedTransition, StrategyModel, TakeProfitMode, exposure_guard,
    average_candle_distances, normalize_pending_records, recover_prepared_transition,
    cycle_directions,
)


def test_mt5_gui_migrates_legacy_state_without_fingerprint_once():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    migration = re.search(
        r"bool MigrateLegacyGuiConfig\(.*?\n\s*\}\n\n",
        source,
        flags=re.DOTALL,
    )

    assert migration, "MT5 GUI must provide a legacy-config migration path"
    body = migration.group(0)
    assert "configfingerprint" in body
    assert "GlobalVariableSet" in body
    assert "return true" in body

    validation = re.search(
        r"bool ValidatePersistedConfigForMagic\(.*?\n\s*\}\n\nvoid SaveState",
        source,
        flags=re.DOTALL,
    )
    assert validation
    assert "MigrateLegacyGuiConfig" in validation.group(0)


def test_mt5_gui_initial_load_allows_recovery_of_active_scope():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    apply_config = re.search(
        r"bool ApplyGuiConfig\(.*?\n\s*\}\n\nGuiConfig LoadConfigFromInputs",
        source,
        flags=re.DOTALL,
    )

    assert apply_config
    first_line = re.search(
        r"const bool allow_initial_scope_recovery = (.*?);",
        apply_config.group(0),
        flags=re.DOTALL,
    )
    assert first_line
    assert "HasManagedExposureForMagic(config.magic_number)" in first_line.group(1)


def test_mt5_gui_keeps_editable_pages_stable_between_user_events():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render_if_needed = re.search(
        r"void GuiRenderIfNeeded\(\).*?\n\s*\}\n\nvoid GuiMarkDraftChanged",
        source,
        flags=re.DOTALL,
    )

    assert render_if_needed
    body = render_if_needed.group(0)
    assert "g_gui_page != GUI_PAGE_OVERVIEW" in body
    assert "g_gui_dirty" in body
    assert "return;" in body


def test_mt5_gui_exposes_every_input_parameter_on_an_editable_page():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render_content = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\nbool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )

    assert render_content, "MT5 GUI content renderer must remain discoverable"
    body = render_content.group(0)
    for key in (
        "first_direction", "cycle_mode", "distance_mode", "order_type",
        "candle_order_mode", "candle_enable_multiple", "take_profit_mode",
        "favorable_grid_enable",
        "initial_lots", "initial_lots_multiplier", "max_reversals",
        "grid_count", "grid_lot_multiplier", "stop_loss_distance_points",
        "take_profit_distance_points", "candle_min_range_points",
        "candle_max_range_points", "average_candle_count",
        "average_stop_multiplier", "average_take_profit_multiplier",
        "magic_number", "order_comment",
        "start_time", "end_time",
    ):
        assert f'"{key}"' in body, f"GUI is missing input parameter: {key}"


def test_mt5_gui_uses_dropdown_option_lists_for_all_selectable_modes():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiRenderDropdownField" in source
    assert "bool GuiHandleDropdownClick" in source
    assert '"dropdown."' in source
    for key in (
        "first_direction", "cycle_mode", "distance_mode", "order_type",
        "candle_order_mode", "candle_enable_multiple", "take_profit_mode",
        "favorable_grid_enable",
    ):
        assert f'"{key}"' in re.search(
            r"int GuiDropdownOptionCount\(.*?\n\s*\}\n\n",
            source,
            flags=re.DOTALL,
        ).group(0)


def test_mt5_gui_dropdown_clicks_are_dispatched_before_redraw():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "GuiHandleDropdownClick(sparam)" in body
    assert body.index("GuiHandleDropdownClick(sparam)") < body.index("GuiHandleEnumClick(sparam)")


def test_mt5_gui_overview_includes_applied_configuration_summary():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    overview = re.search(
        r"if\(g_gui_page == GUI_PAGE_OVERVIEW\).*?\n\s*\}\n\s*else if\(g_gui_page == GUI_PAGE_OPENING\)",
        source,
        flags=re.DOTALL,
    )

    assert overview, "GUI overview page must remain discoverable"
    body = overview.group(0)
    for key in (
        "overview.cycle_mode", "overview.distance_mode", "overview.order_type",
        "overview.initial_lots", "overview.grid_count", "overview.stops",
        "overview.schedule",
    ):
        assert f'"{key}"' in body, f"Overview is missing applied configuration: {key}"


def test_mt5_gui_interactive_objects_have_explicit_event_priority():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    button = re.search(
        r"bool GuiCreateButton\(.*?\n\s*\}\n\nbool GuiCreateEdit",
        source,
        flags=re.DOTALL,
    )
    edit = re.search(
        r"bool GuiCreateEdit\(.*?\n\s*\}\n\nbool GuiTrackCreateResult",
        source,
        flags=re.DOTALL,
    )

    assert button and edit
    assert "OBJPROP_SELECTABLE, true" in button.group(0)
    assert "OBJPROP_ZORDER, 1000" in button.group(0)
    assert "OBJPROP_SELECTABLE, true" in edit.group(0)
    assert "OBJPROP_ZORDER, 1000" in edit.group(0)


def test_mt5_gui_has_chart_coordinate_fallback_for_control_clicks():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiHandleChartClick" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "id == CHARTEVENT_CLICK" in body
    assert "GuiHandleChartClick((int)lparam, (int)dparam)" in body


def test_mt5_gui_chart_fallback_covers_navigation_and_actions():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_click = re.search(
        r"^bool GuiHandleChartClick\(.*?\n\s*\}\n\nbool GuiApplyDraft",
        source,
        flags=re.DOTALL | re.MULTILINE,
    )
    assert chart_click
    body = chart_click.group(0)
    assert "nav." in body
    assert "g_gui_page = (GuiPage)index" in body
    assert '"mode.toggle"' in body
    assert '"apply"' in body
    assert '"pause"' in body


def test_mt5_gui_chart_fallback_does_not_swallow_object_click_dispatch():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"if\(id == CHARTEVENT_CLICK\)\n\s*\{.*?\n\s*\}\n\s*if\(id == CHARTEVENT_KEYDOWN",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiRender();\n      return;" not in body


def test_mt5_gui_edit_focus_does_not_turn_edit_boxes_into_draggable_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_click = re.search(
        r"bool GuiHandleChartClick\(.*?\n\s*\}\n\nbool GuiApplyDraft",
        source,
        flags=re.DOTALL,
    )
    assert chart_click
    body = chart_click.group(0)
    assert "OBJPROP_SELECTED, true" not in body
    assert "OBJPROP_READONLY, false" in body


def test_mt5_gui_releases_button_state_after_object_click_dispatch():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiReleaseButtonState(sparam)" in body


def test_mt5_gui_mode_toggle_has_visible_mode_hint():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert '"mode.hint"' in source
    assert "全部参数仍可编辑" in source


def test_mt5_gui_dropdown_layer_is_above_other_interactive_controls():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    dropdown = re.search(
        r"bool GuiCreateDropdownOption\(.*?\n\s*\}\n\nbool GuiRenderDropdownField",
        source,
        flags=re.DOTALL,
    )

    assert dropdown
    assert "OBJPROP_ZORDER, 2000" in dropdown.group(0)


def test_mt5_gui_dropdown_options_are_rendered_after_all_page_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    field = re.search(
        r"bool GuiRenderDropdownField\(.*?\n\s*\}\n\nbool GuiDropdownFieldPosition",
        source,
        flags=re.DOTALL,
    )
    overlay = re.search(
        r"bool GuiRenderDropdownOverlay\(.*?\n\s*\}\n\nbool GuiRenderLabelValue",
        source,
        flags=re.DOTALL,
    )
    content = re.search(
        r"bool GuiRenderContent\(.*?\n\s*\}\n\nbool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert field and overlay and content
    assert "GuiCreateDropdownOption" not in field.group(0)
    assert "GuiCreateDropdownOption" in overlay.group(0)
    assert "GuiRenderDropdownOverlay(ok)" in content.group(0)


def test_mt5_gui_field_click_dispatch_is_before_active_edit_guard():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiHandleFieldClick(sparam)" in body
    assert body.index("GuiHandleFieldClick(sparam)") < body.index(
        "id == CHARTEVENT_OBJECT_CLICK && StringLen(g_gui_edit_key) > 0"
    )


def test_mt5_gui_field_clicks_switch_edit_and_dropdown_sessions_cleanly():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    field_click = re.search(
        r"bool GuiHandleFieldClick\(.*?\n\s*\}\n\nbool GuiHandleChartClick",
        source,
        flags=re.DOTALL,
    )
    assert field_click
    body = field_click.group(0)
    assert "g_gui_dropdown_key = \"\"" in body
    assert "g_gui_edit_key = \"\"" in body
    assert "GuiLeaveEditSession()" in body
    assert "OBJPROP_READONLY, false" in body


def test_mt5_gui_edit_click_keeps_native_edit_focus_without_recreating_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    dispatch = body[body.index("if(id == CHARTEVENT_OBJECT_CLICK && GuiHandleFieldClick(sparam))") :]
    assert "if(!GuiIsEditableFieldKey" in dispatch
    assert dispatch.index("if(!GuiIsEditableFieldKey") < dispatch.index("GuiRender();")


def test_mt5_gui_does_not_toggle_a_dropdown_twice_for_one_mouse_click():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiShouldSkipChartClick" in source
    assert "void GuiRememberObjectClick" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiRememberObjectClick(lparam, (long)dparam)" in body
    assert "GuiShouldSkipChartClick(lparam, (long)dparam)" in body
    assert body.index("GuiRememberObjectClick(lparam, (long)dparam)") < body.index(
        "if(id == CHARTEVENT_CLICK)"
    )


def test_mt5_gui_declares_all_requested_editable_dropdown_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    keys = [
        "initial_lots", "initial_lots_multiplier",
        "stop_loss_distance_points", "take_profit_distance_points",
        "candle_min_range_points", "candle_max_range_points",
        "average_candle_count", "average_stop_multiplier",
        "average_take_profit_multiplier",
        "grid_count", "grid_lot_multiplier", "max_reversals",
        "start_time", "end_time",
    ]
    assert "bool GuiIsEditableDropdownKey" in source
    for key in keys:
        assert f'"{key}"' in source
    assert "0.03" in source


def test_mt5_gui_editable_dropdowns_have_requested_common_options():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    for value in ["0.01", "0.02", "0.03", "0.04", "0.05", "0.1", "0.2", "0.3", "0.4", "0.5"]:
        assert value in source
    for value in ["1.2", "1.3", "1.5", "2.0", "1500", "5.0"]:
        assert value in source
    assert "for(int hour = 0; hour < 24; hour++)" in source
    assert 'StringFormat("%02d:00", hour)' in source
    assert "int GuiDropdownOptionColumns" in source
    assert "return 2;" in source


def test_mt5_gui_editable_dropdown_uses_large_dedicated_arrow():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "GUI_DROPDOWN_ARROW_WIDTH" in source
    assert "bool GuiCreateDropdownArrow" in source
    assert "GUI_DROPDOWN_ARROW_FONT_SIZE = 30" in source
    assert "GuiCreateDropdownArrow" in source


def test_mt5_gui_all_dropdowns_use_the_same_large_arrow():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    dropdown = re.search(
        r"bool GuiRenderDropdownField\(.*?\n\s*\}\n\n"
        r"bool GuiRenderEditableDropdownField",
        source,
        flags=re.DOTALL,
    )
    assert dropdown
    body = dropdown.group(0)
    assert "GuiCreateDropdownArrow" in body
    assert "GUI_DROPDOWN_ARROW_WIDTH" in body
    assert 'value + " ▾"' not in body


def test_mt5_gui_overview_updates_data_in_place_without_rebuilding_panel():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiRefreshOverviewData" in source
    refresh = re.search(
        r"\nbool GuiRefreshOverviewData\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiMarkDirty",
        source,
        flags=re.DOTALL,
    )
    assert refresh
    body = refresh.group(0)
    assert "metric.value.direction" in body
    assert "overview.positions" in body
    assert "overview.profit" in body
    assert "ObjectsDeleteAll" not in body
    render_if_needed = re.search(
        r"void GuiRenderIfNeeded\(\).*?\n\s*\}\n\nvoid GuiMarkDraftChanged",
        source,
        flags=re.DOTALL,
    )
    assert render_if_needed
    body = render_if_needed.group(0)
    assert "GuiRefreshOverviewData" in body


def test_mt5_gui_editable_dropdown_accepts_valid_custom_values_and_rejects_invalid_text():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiParseEditableDropdownValue" in source
    assert "GuiParseEditableDropdownValue(key, value" in source
    assert "GuiHandleEditKeyDown" in source
    assert "key_code == 27" in source


def test_mt5_gui_panel_fits_compact_chart_viewport():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "GUI_WINDOW_WIDTH = 760" in source
    assert "GUI_WINDOW_HEIGHT = 640" in source
    assert "GUI_NAV_WIDTH = 178" in source
    assert "GUI_CONTENT_WIDTH = 560" in source


def test_mt5_gui_keeps_edit_session_alive_until_text_edit_ends():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert 'g_gui_edit_key' in source
    assert "bool GuiSyncEditValue" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "id == CHARTEVENT_KEYDOWN" in body
    assert "GuiSyncEditValue(g_gui_edit_key)" in body


def test_mt5_gui_temporarily_hides_chart_trade_overlays_and_restores_them():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "CHART_SHOW_TRADE_LEVELS" in source
    assert "CHART_SHOW_TRADE_HISTORY" in source
    assert "GuiPrepareChartForWindow" in source
    assert "GuiRestoreChartAfterWindow" in source
    assert "GuiSetChartOverlayProperty(CHART_SHOW_TRADE_LEVELS, false)" in source
    assert "GuiSetChartOverlayProperty(CHART_SHOW_TRADE_HISTORY, false)" in source


def test_mt5_gui_chart_overlay_state_is_prepared_and_restored_with_lifecycle():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    create = re.search(
        r"bool GuiCreate\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiDestroy",
        source,
        flags=re.DOTALL,
    )
    destroy = re.search(
        r"void GuiDestroy\(\)\n\s*\{.*?\n\s*\}\n\nvoid OnChartEvent",
        source,
        flags=re.DOTALL,
    )

    assert create and destroy
    assert "GuiPrepareChartForWindow" in create.group(0)
    assert "GuiRestoreChartAfterWindow" in destroy.group(0)


def test_mt5_gui_uses_dark_terminal_palette_and_readable_controls():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "color GuiColorPanel()" in source
    assert "color GuiColorSurface()" in source
    assert "color GuiColorInput()" in source
    assert "color GuiColorPrimary()" in source
    assert "color GuiColorDanger()" in source
    assert "OBJPROP_FONTSIZE, 10" in source
    assert "GuiColorInput()" in source
    assert "GuiColorPrimary()" in source
    assert "GuiColorDanger()" in source


def test_mt5_gui_has_terminal_header_context_and_overview_summary():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    overview = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert title and overview
    assert "GuiSymbolPeriodText()" in title.group(0)
    for key in (
        "overview.state", "overview.direction", "overview.positions",
        "overview.orders", "overview.profit", "overview.reversal",
        "overview.cycle_mode", "overview.distance_mode",
        "overview.initial_lots", "overview.grid_count", "overview.stops",
        "overview.schedule",
    ):
        assert key in overview.group(0)


def test_mt5_gui_layout_keeps_panel_and_actions_inside_window():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert 'g_gui_object_prefix + "window", 18, 18' in source
    assert 'GUI_WINDOW_WIDTH, GUI_WINDOW_HEIGHT' in source
    assert 'const int y = GUI_WINDOW_HEIGHT - 44' in source
    for action in ("apply", "pause", "close"):
        assert f'GuiCreateButton(g_gui_object_prefix + "{action}"' in source


def test_mt5_gui_uses_dropdowns_for_enum_parameters_and_edits_for_values():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    content = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert content
    body = content.group(0)
    for key in (
        "first_direction", "cycle_mode", "order_type", "candle_order_mode",
        "candle_enable_multiple", "distance_mode", "take_profit_mode",
    ):
        assert f'GuiRenderEnumField("{key}"' in body
    for key in (
        "initial_lots", "initial_lots_multiplier", "grid_count",
        "grid_lot_multiplier", "max_reversals", "magic_number", "order_comment",
    ):
        renderer = "GuiRenderEditField" if key in ("magic_number", "order_comment") \
            else "GuiRenderEditableDropdownField"
        assert f'{renderer}("{key}"' in body


def test_mt5_gui_keeps_dropdowns_and_edits_above_chart_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);" in source
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 2000);" in source
    assert "CHART_SHOW_TRADE_LEVELS" in source
    assert "CHART_SHOW_TRADE_HISTORY" in source


def test_mt5_gui_text_layers_are_above_panels():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    panel = re.search(
        r"bool GuiCreatePanel\(.*?\n\s*\}\n\nbool GuiCreateText",
        source,
        flags=re.DOTALL,
    )
    text = re.search(
        r"bool GuiCreateText\(.*?\n\s*\}\n\nbool GuiCreateButton",
        source,
        flags=re.DOTALL,
    )
    assert panel and text
    assert "OBJPROP_ZORDER, 10" in panel.group(0)
    assert "OBJPROP_ZORDER, 500" in text.group(0)


def test_mt5_gui_does_not_render_default_label_for_clean_dirty_status():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    assert title
    assert 'g_gui_has_unapplied_changes ? "· 未应用" : " "' in title.group(0)


def test_mt5_gui_matches_browser_shell_geometry():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    navigation = re.search(
        r"bool GuiRenderNavigation\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderCloseConfirmation",
        source,
        flags=re.DOTALL,
    )
    content = re.search(
        r"bool GuiRenderContent\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert title and navigation and content
    assert 'GUI_WINDOW_WIDTH' in title.group(0)
    assert 'GUI_NAV_WIDTH' in navigation.group(0)
    assert 'GUI_CONTENT_WIDTH' in content.group(0)
    assert 'const int GUI_CONTENT_X = GUI_NAV_WIDTH + 18' in source


def test_mt5_gui_overview_contains_browser_summary_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    overview = re.search(
        r"if\(g_gui_page == GUI_PAGE_OVERVIEW\).*?\n\s*\}\n\s*else if\(g_gui_page == GUI_PAGE_OPENING\)",
        source,
        flags=re.DOTALL,
    )
    assert overview
    body = overview.group(0)
    for key in (
        "overview.order_group", "overview.cycle",
        "overview.initial_lots_multiplier", "overview.grid_lot_multiplier",
        "overview.take_profit_mode", "overview.magic_number",
        "overview.order_comment",
    ):
        assert f'"{key}"' in body, f"Browser-parity overview is missing {key}"


def test_mt5_gui_rejects_invalid_numeric_edits_without_coercing_to_zero():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiTryParseDouble" in source
    assert "bool GuiTryParseInteger" in source
    sync = re.search(
        r"bool GuiSyncEditValue\(.*?\n\s*\}\n\nbool GuiHandleEditEnd",
        source,
        flags=re.DOTALL,
    )
    assert sync
    assert "GuiTryParseDouble" in sync.group(0)
    assert "GuiTryParseInteger" in sync.group(0)
    assert "g_gui_notice" in sync.group(0)


def test_mt5_gui_preserves_active_edit_control_during_redraw():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render = re.search(
        r"bool GuiRender\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiRenderIfNeeded",
        source,
        flags=re.DOTALL,
    )
    assert render
    body = render.group(0)
    assert "GuiRenderActiveEdit" in body
    assert "g_gui_edit_key" in source


def test_mt5_gui_surfaces_chart_overlay_preparation_failure():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    create = re.search(
        r"bool GuiCreate\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiDestroy",
        source,
        flags=re.DOTALL,
    )
    prepare = re.search(
        r"bool GuiPrepareChartForWindow\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiRestoreChartAfterWindow",
        source,
        flags=re.DOTALL,
    )
    assert create and prepare
    assert "if(!GuiPrepareChartForWindow())" in create.group(0)
    assert "GuiSetChartOverlayProperty" in prepare.group(0)
    assert "GetLastError" in prepare.group(0)
    assert "GuiSetChartOverlayProperty" in prepare.group(0)
    assert "GuiRestoreChartAfterWindow" in prepare.group(0)


def test_mt5_gui_rejects_integer_overflow_and_keeps_magic_number_wide():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiTryParseLong" in source
    sync = re.search(
        r"bool GuiSyncEditValue\(.*?\n\s*\}\n\nbool GuiHandleEditEnd",
        source,
        flags=re.DOTALL,
    )
    assert sync
    body = sync.group(0)
    assert "GuiTryParseLong(value, parsed_long)" in body
    assert "g_gui_draft_config.magic_number" in body
    assert "INT_MAX" in source or "2147483647" in source


def test_mt5_gui_blocks_navigation_while_active_edit_is_invalid():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiLeaveEditSession" in body
    assert body.index("GuiLeaveEditSession") < body.index("g_gui_edit_key = \"\";")


def test_mt5_gui_object_prefix_is_bounded_for_mql5_object_names():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    prefix = re.search(
        r"string GuiObjectPrefix\(\)\n\s*\{.*?\n\s*\}",
        source,
        flags=re.DOTALL,
    )
    assert prefix
    body = prefix.group(0)
    assert "StringSubstr" in body
    assert "% 1000000" in body


def test_mt5_gui_rebuilds_object_prefix_after_magic_number_change():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    apply_start = source.index("bool ApplyGuiConfig")
    apply_end = source.index("GuiConfig LoadConfigFromInputs", apply_start)
    apply = source[apply_start:apply_end]
    assert "g_gui_object_prefix" in apply
    assert "GuiObjectPrefix()" in apply


def test_mt5_gui_object_prefix_stays_short_for_mql5_object_names():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    prefix = re.search(
        r"string GuiObjectPrefix\(\)\n\s*\{.*?\n\s*\}",
        source,
        flags=re.DOTALL,
    )
    assert prefix
    assert 'return "NMR.g."' in prefix.group(0)
    assert "ObjectsDeleteAll(0, legacy_prefix)" in source


def test_cycle_templates_cover_both_modes_and_first_directions():
    assert cycle_directions(Direction.BUY, CycleMode.MODE_1) == [
        Direction.BUY, Direction.SELL, Direction.SELL,
        Direction.BUY, Direction.SELL, Direction.SELL,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_1) == [
        Direction.SELL, Direction.BUY, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert cycle_directions(Direction.BUY, CycleMode.MODE_2) == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_2) == [
        Direction.SELL, Direction.BUY, Direction.SELL,
        Direction.BUY, Direction.SELL, Direction.SELL,
    ]
    assert cycle_directions(Direction.BUY, CycleMode.MODE_3) == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.BUY, Direction.SELL, Direction.BUY,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_3) == [
        Direction.SELL, Direction.BUY, Direction.SELL,
        Direction.SELL, Direction.BUY, Direction.SELL,
    ]


def test_mode_one_buy_uses_sell_stop_then_sell_limit_for_the_two_sell_steps():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    second_actions = model.on_tick(bid=1.0502, ask=1.0504)

    assert first_actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert first_actions[1] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.01,
        "price": 1.0502, "order_type": "SELL_STOP",
    }
    assert second_actions[0] == {"kind": "delete_pending"}
    assert second_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert second_actions[2] == {"kind": "market", "direction": Direction.SELL, "lots": 0.01}
    assert second_actions[3] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.02,
        "price": 1.1002, "order_type": "SELL_LIMIT",
    }


def test_stop_deletes_unfilled_reverse_pending_before_market_reversal():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[0] == {"kind": "delete_pending"}
    assert stop_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert stop_actions[2]["kind"] == "market"


def test_mode_two_buy_reaches_buy_buy_and_wraps_after_six_orders():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        max_reversals=6,
    )
    directions = []

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    directions.append(actions[0]["direction"])
    for _ in range(5):
        position = model.position
        if position.direction is Direction.BUY:
            bid, ask = position.stop_loss, position.stop_loss + 0.0002
        else:
            bid, ask = position.stop_loss - 0.0002, position.stop_loss
        actions = model.on_tick(bid=bid, ask=ask)
        directions.append(actions[2]["direction"])

    assert directions == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert model.current_index == 5

    position = model.position
    actions = model.on_tick(bid=position.stop_loss, ask=position.stop_loss + 0.0002)
    assert actions[2]["direction"] == Direction.BUY
    assert model.current_index == 0


def test_grid_multiplier_is_applied_to_the_next_group_grid_lot():
    model = StrategyModel(Direction.SELL, CycleMode.MODE_1, 0.03, 3.0, 500, 0.0001,
                          grid_count=2, first_order_lot_type=1)

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    model.on_tick(bid=1.1250, ask=1.1252)
    model.fill_grid_pending()
    next_actions = model.on_tick(bid=1.1500, ask=1.1502)

    assert first_actions[1]["lots"] == 0.03
    assert next_actions[2]["lots"] == pytest.approx(0.06)
    assert model.grid_lots == pytest.approx(0.09)


def test_only_a_post_stop_group_uses_the_initial_lot_multiplier():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, initial_lot_multiplier=1.5, first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert first_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }
    assert first_actions[1]["lots"] == pytest.approx(0.015)

    first_stop = model.position.stop_loss
    next_actions = model.on_tick(bid=first_stop, ask=first_stop + 0.0002)

    assert next_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": pytest.approx(0.015),
    }


def test_type_two_uses_previous_group_first_lot_after_grid_loss():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, first_order_lot_type=2, first_order_mult=2.0,
    )

    initial_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert initial_actions[1]["lots"] == pytest.approx(0.02)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": pytest.approx(0.02),
    }


def test_default_first_order_lot_type_uses_previous_group_first_lot():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2]["lots"] == pytest.approx(0.02)


def test_type_two_uses_immediately_previous_group_first_lot_on_consecutive_stops():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, first_order_lot_type=2, first_order_mult=2.0,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    first_stop = model.position.stop_loss
    second_group = model.on_tick(bid=first_stop, ask=first_stop + 0.0002)
    assert second_group[2]["lots"] == pytest.approx(0.02)

    second_stop = model.position.stop_loss
    third_group = model.on_tick(bid=second_stop - 0.0002, ask=second_stop)
    assert third_group[2]["lots"] == pytest.approx(0.04)


def test_type_one_preserves_accumulated_group_total_formula():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, initial_lot_multiplier=1.0,
        first_order_lot_type=1, first_order_mult=2.0,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2]["lots"] == pytest.approx(0.02)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_first_order_lot_type_is_present_in_both_expert_sources(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "FirstOrderLotType" in source
    assert "FirstOrderMult" in source
    assert "first_order_lots" in source or "group_first_lots" in source
    assert "input int            止损首单类型 = 2;" in source
    assert "input double         首单类型2倍数 = 2.0;" in source
    assert "== 2" in source


def test_initial_entry_is_allowed_only_inside_the_configured_time_window():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )

    assert model.on_tick(bid=1.1000, ask=1.1002, now_minute=7 * 60 + 59) == []
    actions = model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)

    assert actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }


def test_existing_position_can_switch_groups_outside_the_initial_entry_window():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )

    model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)
    stop_price = model.position.stop_loss
    actions = model.on_tick(
        bid=stop_price, ask=stop_price + 0.0002, now_minute=23 * 60 + 30,
    )

    assert actions[2]["kind"] == "market"
    assert actions[2]["direction"] is Direction.SELL


def test_first_group_grid_add_uses_initial_lot_and_moves_tp_and_next_group_lot():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert first_actions[0]["lots"] == pytest.approx(0.01)
    assert first_actions[1]["lots"] == pytest.approx(0.01)
    assert first_actions[2] == {
        "kind": "grid_pending", "direction": Direction.BUY,
        "lots": 0.01, "price": 1.0902,
        "order_type": "BUY_LIMIT", "level": 1,
    }

    grid_actions = model.fill_grid_pending()

    assert grid_actions[0] == {
        "kind": "grid",
        "direction": Direction.BUY,
        "lots": 0.01,
        "price": 1.0902,
    }
    assert model.position.take_profit == pytest.approx(1.1402)
    assert model.pending.lots == pytest.approx(0.02)
    assert model.grid_pending.level == 2
    assert model.grid_pending.price == pytest.approx(1.0802)
    assert model.grid_pending.lots == pytest.approx(0.01)


def test_grid_count_five_places_all_internal_levels_at_once():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    grid_actions = [action for action in actions if action["kind"] == "grid_pending"]

    assert [action["level"] for action in grid_actions] == [1, 2, 3, 4]
    assert [action["price"] for action in grid_actions] == [
        pytest.approx(1.0902), pytest.approx(1.0802),
        pytest.approx(1.0702), pytest.approx(1.0602),
    ]
    assert all(action["order_type"] == "BUY_LIMIT" for action in grid_actions)


def test_filling_one_grid_level_keeps_other_pending_levels_without_replacement():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending(level=2)

    pending_levels = sorted(
        pending.level
        for pending in getattr(model, "grid_pendings", {}).values()
    )
    assert pending_levels == [1, 3, 4]

    model.on_tick(bid=1.0950, ask=1.0952)
    pending_levels_after_tick = sorted(
        pending.level
        for pending in getattr(model, "grid_pendings", {}).values()
    )
    assert pending_levels_after_tick == [1, 3, 4]


def test_linear_buy_tp_follows_adverse_move_and_does_not_retrace():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        take_profit_mode=TakeProfitMode.LINEAR,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.position.take_profit == pytest.approx(1.1502)

    model.on_tick(bid=1.0950, ask=1.0952)
    assert model.position.take_profit == pytest.approx(1.1452)

    model.on_tick(bid=1.0980, ask=1.0982)
    assert model.position.take_profit == pytest.approx(1.1452)


def test_linear_sell_tp_follows_adverse_move_and_does_not_retrace():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        take_profit_mode=TakeProfitMode.LINEAR,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.position.take_profit == pytest.approx(1.0500)

    model.on_tick(bid=1.1050, ask=1.1052)
    assert model.position.take_profit == pytest.approx(1.0550)

    model.on_tick(bid=1.1020, ask=1.1022)
    assert model.position.take_profit == pytest.approx(1.0550)


def test_grid_take_profit_stays_fixed_until_grid_fill():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, take_profit_mode=TakeProfitMode.GRID,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.on_tick(bid=1.0950, ask=1.0952)
    assert model.position.take_profit == pytest.approx(1.1502)

    model.fill_grid_pending()
    assert model.position.take_profit == pytest.approx(1.1402)


def test_losing_group_initial_lots_accumulate_and_grid_lots_double():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    first_group_stop = model.position.stop_loss
    second_group_actions = model.on_tick(
        bid=first_group_stop, ask=first_group_stop + 0.0002,
    )

    assert second_group_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": 0.02,
    }
    assert model.grid_lots == pytest.approx(0.02)

    model.fill_grid_pending()
    second_group_stop = model.position.stop_loss
    third_group_actions = model.on_tick(
        bid=second_group_stop - 0.0002, ask=second_group_stop,
    )

    assert third_group_actions[2] == {
        "kind": "market", "direction": Direction.SELL,
        "lots": pytest.approx(0.06),
    }
    assert model.grid_lots == pytest.approx(0.04)


def test_grid_count_is_number_of_intervals_and_outer_boundary_still_stops_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.grid_pending.level == 1
    grid_actions = model.fill_grid_pending()
    assert grid_actions[0]["kind"] == "grid"
    assert model.grid_pending is None
    assert model.current_index == 0

    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )
    assert stop_actions[0] == {"kind": "delete_pending"}
    assert stop_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert stop_actions[2]["kind"] == "market"
    assert stop_actions[2]["direction"] is Direction.SELL


def test_favorable_grid_additions_are_disabled_by_default():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert [action for action in actions if action["kind"] == "favorable_grid_pending"] == []
    assert len([action for action in actions if action["kind"] == "grid_pending"]) == 3


@pytest.mark.parametrize(
    ("direction", "expected_order_type"),
    [(Direction.BUY, "BUY_STOP"), (Direction.SELL, "SELL_STOP")],
)
def test_favorable_grid_additions_use_the_same_grid_count_and_lot_size(
    direction, expected_order_type,
):
    model = StrategyModel(
        direction, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    favorable = [
        action for action in actions if action["kind"] == "favorable_grid_pending"
    ]

    assert len(favorable) == 3
    assert all(action["direction"] is direction for action in favorable)
    assert all(action["order_type"] == expected_order_type for action in favorable)
    assert all(action["lots"] == pytest.approx(0.01) for action in favorable)


def test_favorable_grid_source_uses_a_chinese_visible_input_label():
    for source_name in ("NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"):
        source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
        assert "input int            有利方向加单 = 0;" in source
        assert "FavorableGridEnable" in source
    mt5_source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )
    assert "有利方向加单" in mt5_source
    assert "关闭" in mt5_source and "开启" in mt5_source


def test_favorable_grid_fill_updates_the_same_group_total_and_tp_flow():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    fill_actions = model.fill_favorable_grid_pending(level=1)

    assert fill_actions[0]["kind"] == "favorable_grid"
    assert model.group_total_lots == pytest.approx(0.02)
    assert model.favorable_grid_filled_levels == 1
    assert model.position.take_profit > model.position.entry


def test_grid_count_is_bounded_by_grid_fill_mask_capacity():
    mt4_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT4.mq4").read_text(encoding="utf-8")
    mt5_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT5.mq5").read_text(encoding="utf-8")

    assert "#define MAX_GRID_COUNT 63" in mt4_source
    assert "#define MAX_GRID_COUNT 63" in mt5_source
    assert "InpGridCount > MAX_GRID_COUNT" in mt4_source
    assert "config.grid_count > MAX_GRID_COUNT" in mt5_source
    assert 'if(key == "grid_count" && parsed > MAX_GRID_COUNT)' in mt5_source


def test_grid_fill_mask_persistence_uses_exact_integer_parts():
    mt4_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT4.mq4").read_text(encoding="utf-8")
    mt5_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT5.mq5").read_text(encoding="utf-8")

    for source in (mt4_source, mt5_source):
        assert ".gridmask.low" in source
        assert ".gridmask.high" in source
        assert "mask = (high << 32) | low;" in source
        assert "SaveGridMask(prefix, g_grid_filled_mask);" in source
        assert "GlobalVariableSet(prefix + \".gridmask\", (double)" not in source


def test_take_profit_resets_loss_accumulation_for_the_next_cycle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    first_stop = model.position.stop_loss
    model.on_tick(bid=first_stop, ask=first_stop + 0.0002)
    second_take_profit = model.position.take_profit
    model.on_tick(bid=second_take_profit - 0.0002, ask=second_take_profit)

    new_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert new_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": 0.01,
    }


def test_take_profit_ends_cycle_and_removes_reverse_pending():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    actions = model.on_tick(bid=1.1502, ask=1.1504)

    assert actions == [{"kind": "cancel_pending"}]
    assert model.position is None
    assert model.pending is None


@pytest.mark.parametrize("range_points", [499, 1001])
def test_candle_range_mode_skips_a_new_order_outside_inclusive_bounds(range_points):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        first_order_lot_type=1,
        max_range_points=1000,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions == []
    assert model.position is None
    assert model.pending is None


@pytest.mark.parametrize("range_points", [500, 700, 1000])
def test_candle_range_mode_accepts_boundary_and_middle_values(range_points):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.position.stop_loss == pytest.approx(1.1012 - range_points * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1012 + range_points * 0.0001)


def test_fixed_distance_mode_ignores_an_invalid_candle_range():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.FIXED,
        min_range_points=500,
        max_range_points=1000,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002, candle_range_points=300)

    assert actions[0] == {"kind": "market", "direction": Direction.SELL, "lots": 0.01}


def test_average_candle_distances_uses_only_completed_candles_and_applies_multipliers():
    stop_points, take_profit_points = average_candle_distances(
        [100, 200, 300], candle_count=2, stop_multiplier=2.0,
        take_profit_multiplier=2.0,
    )

    assert stop_points == 300
    assert take_profit_points == 600


@pytest.mark.parametrize(
    ("ranges", "candle_count", "stop_multiplier", "take_profit_multiplier"),
    [
        ([100], 2, 2.0, 2.0),
        ([100, 0], 2, 2.0, 2.0),
        ([100, -20], 2, 2.0, 2.0),
        ([100, 200], 2, 0.0, 2.0),
        ([100, 200], 2, 2.0, -1.0),
    ],
)
def test_average_candle_distances_rejects_invalid_inputs(
    ranges, candle_count, stop_multiplier, take_profit_multiplier,
):
    with pytest.raises(ValueError):
        average_candle_distances(
            ranges, candle_count=candle_count,
            stop_multiplier=stop_multiplier,
            take_profit_multiplier=take_profit_multiplier,
        )


def test_average_distance_mode_uses_market_entry_and_keeps_distances_for_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.AVERAGE_CANDLE_RANGE,
        average_candle_count=3, average_stop_multiplier=2.0,
        average_take_profit_multiplier=2.0, korder_type=0,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, previous_high=1.2000, previous_low=1.0000,
        average_candle_ranges=[100, 200, 300], candle_id=10,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert all(action["kind"] != "initial_pending" for action in actions)
    assert model.group_stop_points == 400
    assert model.group_take_profit_points == 800
    assert model.position.stop_loss == pytest.approx(1.1002 - 400 * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1002 + 800 * 0.0001)


def test_average_distance_mode_does_not_use_single_candle_min_max_filter():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.AVERAGE_CANDLE_RANGE,
        average_candle_count=2, average_stop_multiplier=1.0,
        average_take_profit_multiplier=1.0,
        min_range_points=500, max_range_points=1000,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=1,
        average_candle_ranges=[100, 200],
    )

    assert actions[0]["kind"] == "market"
    assert model.group_stop_points == 150


def test_mt4_and_mt5_expose_matching_average_distance_contract():
    mt4_source = MT4_SOURCE.read_text(encoding="utf-8")
    mt5_source = MT5_SOURCE.read_text(encoding="utf-8")
    for source in (mt4_source, mt5_source):
        assert "DISTANCE_AVERAGE_CANDLE_RANGE" in source
        assert "平均K线根数" in source
        assert "平均止损倍数" in source
        assert "平均止盈倍数" in source
        assert "for(int shift = 1; shift <=" in source
    assert 'config.distance_mode != DISTANCE_AVERAGE_CANDLE_RANGE' in mt5_source
    assert 'key == "average_candle_count"' in mt5_source


@pytest.mark.parametrize(
    ("order_type", "bid", "ask", "expected_first", "expected_cycle"),
    [
        (OrderType.FORWARD, 1.1010, 1.1012, Direction.BUY, CycleMode.MODE_1),
        (OrderType.REVERSE, 1.1010, 1.1012, Direction.SELL, CycleMode.MODE_2),
        (OrderType.FORWARD, 1.0390, 1.0392, Direction.SELL, CycleMode.MODE_1),
        (OrderType.REVERSE, 1.0390, 1.0392, Direction.BUY, CycleMode.MODE_2),
    ],
)
def test_candle_breakout_selects_first_direction_and_cycle_from_order_type(
    order_type, bid, ask, expected_first, expected_cycle,
):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=order_type,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=bid, ask=ask, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions[0] == {"kind": "market", "direction": expected_first, "lots": 0.01}
    assert model.cycle_mode is expected_cycle
    assert model.sequence[0] is expected_first


def test_candle_range_mode_waits_for_a_breakout_before_opening():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions == []
    assert model.position is None
    assert model.pending is None


def test_candle_once_places_buy_at_high_and_sell_at_low_without_market_entry():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert [action["kind"] for action in actions] == [
        "initial_pending", "initial_pending",
    ]
    assert {(action["direction"], action["price"]) for action in actions} == {
        (Direction.BUY, 1.1000), (Direction.SELL, 1.0400),
    }
    assert [pending.kind for pending in model.initial_pending] == [
        "initial_pending", "initial_pending",
    ]
    assert all(action["kind"] != "market" for action in actions)


def test_candle_once_reverse_places_sell_at_high_and_buy_at_low_once():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.REVERSE, korder_type=0,
    )

    first = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    second = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert {(action["direction"], action["price"]) for action in first} == {
        (Direction.SELL, 1.1000), (Direction.BUY, 1.0400),
    }
    assert second == []


def test_candle_repeat_still_waits_for_breakout_and_opens_market_order():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=1,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions == []

    actions = model.on_tick(
        bid=1.1001, ask=1.1003, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions[0]["kind"] == "market"
    assert all(action["kind"] != "initial_pending" for action in actions)


def test_initial_pending_fill_cancels_the_other_side_and_starts_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )
    model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    actions = model.fill_initial_pending(Direction.BUY, 1.1000)

    assert actions[0] == {"kind": "cancel_initial_pending", "direction": Direction.SELL}
    assert model.position.direction is Direction.BUY
    assert model.position.entry == 1.1000
    assert model.initial_pending == []


def test_candle_mode_ignores_user_first_direction_and_cycle_mode_inputs():
    forward_model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )
    forward_actions = forward_model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    reverse_model = StrategyModel(
        Direction.BUY, CycleMode.MODE_3, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.REVERSE,
        korder_type=1,
    )
    reverse_actions = reverse_model.on_tick(
        bid=1.0390, ask=1.0392, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert forward_actions[0]["direction"] is Direction.BUY
    assert forward_model.cycle_mode is CycleMode.MODE_1
    assert reverse_actions[0]["direction"] is Direction.BUY
    assert reverse_model.cycle_mode is CycleMode.MODE_2


def test_candle_range_mode_keeps_running_cycle_when_later_range_is_invalid():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        first_order_lot_type=1,
        max_range_points=1000,
        korder_type=1,
    )

    model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    for _ in range(3):
        pending = model.pending
        model.fill_pending(pending.price)
        model.on_tick(
            bid=model.position.entry,
            ask=model.position.entry + 0.0002,
            candle_range_points=600,
            previous_high=1.1000, previous_low=1.0400,
        )

    pending = model.pending
    model.fill_pending(pending.price)
    actions = model.on_tick(
        bid=model.position.entry,
        ask=model.position.entry + 0.0002,
        candle_range_points=300,
        previous_high=1.1000, previous_low=1.0700,
    )

    assert model.position.lots == pytest.approx(0.08)
    assert actions == []
    assert model.pending.direction is Direction.SELL
    assert model.pending.lots == pytest.approx(0.16)
    assert model.pending.price == pytest.approx(model.position.stop_loss)
    assert model.pending.order_type == "SELL_LIMIT"

    position = model.position
    stop_actions = model.on_tick(
        bid=position.stop_loss,
        ask=position.stop_loss + 0.0002,
        candle_range_points=300,
        previous_high=1.1000, previous_low=1.0700,
    )
    assert stop_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": 0.16,
    }


def test_candle_order_mode_zero_places_initial_pending_once_per_current_candle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD,
        korder_type=0,
    )
    first = model.on_tick(
        bid=1.1002, ask=1.1004, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    same_candle = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert [action["kind"] for action in first] == [
        "initial_pending", "initial_pending",
    ]
    assert same_candle == []
    assert model.position is None
    assert len(model.initial_pending) == 2


def test_candle_order_mode_one_allows_repeated_initial_entries_per_current_candle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )
    model.on_tick(
        bid=1.1002, ask=1.1004, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    model.on_tick(
        bid=model.position.take_profit, ask=model.position.take_profit + 0.0002,
        candle_range_points=600, previous_high=1.1000, previous_low=1.0400,
        candle_id=10,
    )

    repeated = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert repeated[0]["kind"] == "market"


def test_candle_distance_is_locked_until_take_profit_starts_a_new_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        korder_type=1,
    )

    first_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    first_stop = model.position.stop_loss
    first_take_profit = model.position.take_profit

    unchanged_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=900,
        previous_high=1.1000, previous_low=1.0100,
    )

    assert unchanged_actions == []
    assert model.position.stop_loss == pytest.approx(first_stop)
    assert model.position.take_profit == pytest.approx(first_take_profit)
    assert model.pending.distance_points == pytest.approx(600)

    model.on_tick(bid=first_take_profit, ask=first_take_profit + 0.0002, candle_range_points=900)
    new_group_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=900,
        previous_high=1.1000, previous_low=1.0100,
    )

    assert new_group_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": 0.01,
    }
    assert model.position.stop_loss == pytest.approx(1.1012 - 900 * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1012 + 900 * 0.0001)
    assert model.pending.distance_points == pytest.approx(900)


@pytest.mark.parametrize(
    ("initial_direction", "cycle_mode"),
    [
        (Direction.BUY, CycleMode.MODE_1),
        (Direction.SELL, CycleMode.MODE_1),
        (Direction.BUY, CycleMode.MODE_2),
        (Direction.SELL, CycleMode.MODE_2),
        (Direction.BUY, CycleMode.MODE_3),
        (Direction.SELL, CycleMode.MODE_3),
    ],
)
def test_all_four_combinations_run_a_full_six_order_cycle(initial_direction, cycle_mode):
    model = StrategyModel(
        initial_direction, cycle_mode, 0.01, 2.0, 500, 0.0001,
        max_reversals=6, first_order_lot_type=1,
    )
    opened = []
    pending_types = []

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    opened.append((actions[0]["direction"], actions[0]["lots"]))
    pending_types.append(actions[1]["order_type"])
    for _ in range(5):
        position = model.position
        if position.direction is Direction.BUY:
            bid, ask = position.stop_loss, position.stop_loss + 0.0002
        else:
            bid, ask = position.stop_loss - 0.0002, position.stop_loss
        actions = model.on_tick(bid=bid, ask=ask)
        opened.append((actions[2]["direction"], actions[2]["lots"]))
        pending_types.append(actions[3]["order_type"])

    expected = cycle_directions(initial_direction, cycle_mode)
    assert [direction for direction, _ in opened] == expected
    assert [lots for _, lots in opened] == pytest.approx([0.01, 0.01, 0.02, 0.04, 0.08, 0.16])
    expected_pending_types = []
    for current, following in zip(expected, expected[1:] + expected[:1]):
        if current is Direction.BUY and following is Direction.BUY:
            expected_pending_types.append("BUY_LIMIT")
        elif current is Direction.SELL and following is Direction.SELL:
            expected_pending_types.append("SELL_LIMIT")
        elif following is Direction.BUY:
            expected_pending_types.append("BUY_STOP")
        else:
            expected_pending_types.append("SELL_STOP")
    assert pending_types == expected_pending_types


def test_no_money_closes_group_resets_state_and_restarts_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )

    first = model.on_tick(bid=1.1000, ask=1.1002)
    assert first == [{"kind": "no_money"}]
    assert model.position is None
    assert model.pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)
    assert model.current_index == 0

    second = model.on_tick(bid=1.1000, ask=1.1002)
    assert second[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }


def test_no_money_after_stop_starts_a_fresh_base_lot_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        initial_lot_multiplier=2.0, grid_count=5,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    model.market_order_failures = 1
    stop_price = model.position.stop_loss

    failed = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert failed == [{"kind": "no_money"}]
    assert model.position is None
    assert model.pending is None
    assert model.grid_pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)

    restarted = model.on_tick(bid=1.1000, ask=1.1002)
    assert restarted[0]["lots"] == pytest.approx(0.01)


def test_no_money_dynamic_mode_rechecks_current_breakout_after_reset():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD,
        market_order_failures=1,
        korder_type=1,
    )

    waiting = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert waiting == []

    failed = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert failed == [{"kind": "no_money"}]

    no_breakout = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert no_breakout == []

    restarted = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert restarted[0]["kind"] == "market"
    assert model.group_stop_points == pytest.approx(700)


def test_no_money_reset_does_not_open_again_on_the_same_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert [action["kind"] for action in actions] == ["no_money"]


def test_no_money_reset_uses_fixed_mode_time_window_for_the_new_cycle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )
    model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)
    model.market_order_failures = 1
    stop_price = model.position.stop_loss

    failed = model.on_tick(
        bid=stop_price, ask=stop_price + 0.0002,
        now_minute=23 * 60 + 30,
    )
    assert failed == [{"kind": "no_money"}]

    outside_window = model.on_tick(
        bid=1.1000, ask=1.1002, now_minute=23 * 60 + 30,
    )
    assert outside_window == []

    restarted = model.on_tick(
        bid=1.1000, ask=1.1002, now_minute=8 * 60,
    )
    assert restarted[0]["lots"] == pytest.approx(0.01)


def test_max_reversals_five_allows_five_switches_then_resets():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=5,
    )
    model.on_tick(bid=1.1000, ask=1.1002)

    for expected_count in range(1, 6):
        stop_price = model.position.stop_loss
        actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
        assert actions[2]["kind"] == "market"
        assert model.reversal_count == expected_count

    stop_price = model.position.stop_loss
    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None
    assert model.reversal_count == 0
    assert model.cumulative_loss_lots == pytest.approx(0.0)


def test_zero_max_reversals_resets_after_the_first_group_stop():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss

    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None


def test_max_reversals_counts_reverse_pending_fills_before_reset():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=2,
    )
    model.on_tick(bid=1.1000, ask=1.1002)

    for expected_count in (1, 2):
        pending_price = model.pending.price
        model.fill_pending(pending_price)
        assert model.reversal_count == expected_count

    assert model.pending is None
    stop_price = model.position.stop_loss
    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.reversal_count == 0


def test_filled_reverse_pending_is_the_only_stop_transition_action():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        first_order_lot_type=1,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    pending_price = model.pending.price

    actions = model.handle_stop_event(
        bid=pending_price, ask=pending_price + 0.0002, pending_filled=True,
    )

    assert actions == [{
        "kind": "pending_transition", "direction": Direction.SELL, "lots": 0.01,
    }]
    assert model.reversal_count == 1


def test_new_cycle_after_max_reversals_uses_base_lot_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0, initial_lot_multiplier=2.0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss
    model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert actions[0]["kind"] == "market"
    assert actions[0]["lots"] == pytest.approx(0.01)


def dynamic_parallel_model(multiple, korder_type=1):
    return ParallelStrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD, grid_count=2,
        korder_type=korder_type, kline_enable_multiple=multiple,
    )


def parallel_breakout(model, candle_id, range_points, bid=1.1010, ask=1.1012):
    return model.on_tick(
        bid=bid, ask=ask, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
        candle_id=candle_id,
    )


def test_kline_multiple_zero_blocks_new_group_while_existing_group_is_active():
    model = dynamic_parallel_model(0)
    assert parallel_breakout(model, 10, 600)[0]["kind"] == "market"
    assert parallel_breakout(model, 11, 900) == []
    assert len(model.groups) == 1


def test_kline_multiple_one_opens_independent_group_with_existing_group():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    actions = parallel_breakout(model, 11, 900)
    assert actions[0]["kind"] == "market"
    assert len(model.groups) == 2
    assert [group.group_id for group in model.groups] == [1, 2]


def test_parallel_groups_keep_different_candle_distances():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    assert [group.group_stop_points for group in model.groups] == [600, 900]
    assert [group.group_take_profit_points for group in model.groups] == [600, 900]


def test_take_profit_of_one_group_does_not_close_other_group():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    first, second = model.groups
    actions = model.on_tick(
        bid=first.position.take_profit,
        ask=first.position.take_profit + 0.0002,
        candle_id=11,
    )
    assert actions[0]["group_id"] == first.group_id
    assert first.position is None
    assert second.position is not None
    assert second.pending is not None


def test_parallel_groups_keep_reverse_and_grid_pending_separate():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    first, second = model.groups
    assert first.pending is not None and second.pending is not None
    assert first.grid_pending is not None and second.grid_pending is not None
    first_pending_price = first.pending.price
    model.fill_pending(first.group_id, first_pending_price)
    assert second.pending is not None
    assert second.grid_pending is not None


def test_parallel_multiple_groups_create_two_initial_pending_orders_per_candle():
    model = dynamic_parallel_model(1, korder_type=0)

    first = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    duplicate = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    second = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=700,
        previous_high=1.1100, previous_low=1.0400, candle_id=11,
    )

    assert [action["kind"] for action in first] == [
        "initial_pending", "initial_pending",
    ]
    assert duplicate == []
    assert [action["kind"] for action in second] == [
        "initial_pending", "initial_pending",
    ]
    assert len(model.groups) == 2
    assert all(len(group.initial_pending) == 2 for group in model.groups)


def test_parallel_repeat_mode_still_opens_market_order_after_breakout():
    model = dynamic_parallel_model(1, korder_type=1)

    actions = parallel_breakout(model, 10, 600)

    assert actions[0]["kind"] == "market"
    assert all(action["kind"] != "initial_pending" for action in actions)


def test_parallel_fill_initial_pending_forwards_group_action_and_keeps_followups():
    model = dynamic_parallel_model(1, korder_type=0)
    model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    actions = model.fill_initial_pending(1, Direction.BUY, 1.1000)

    assert actions[0] == {
        "kind": "cancel_initial_pending", "direction": Direction.SELL,
        "group_id": 1,
    }
    assert model.groups[0].position.direction is Direction.BUY
    assert model.groups[0].pending is not None
    assert model.groups[0].grid_pending is not None


def test_parallel_group_stop_deletes_unfilled_pending_before_market_reversal():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    group = model.groups[0]
    actions = model.on_tick(
        bid=group.position.stop_loss,
        ask=group.position.stop_loss + 0.0002,
        candle_id=10,
    )
    group_actions = [action for action in actions if action["group_id"] == group.group_id]
    assert group_actions[0]["kind"] == "delete_pending"
    assert group_actions[1] == {"kind": "close", "direction": Direction.BUY,
                                "group_id": group.group_id}
    assert group_actions[2]["kind"] == "market"
    assert group_actions[2]["direction"] is Direction.SELL


def test_same_scope_allows_only_one_execution_owner():
    registry = ExecutionOwnershipRegistry()
    scope = (111, "XAUUSD", 20260830)

    assert registry.acquire(scope, "chart-a") is True
    assert registry.acquire(scope, "chart-b") is False
    registry.release(scope, "chart-a")
    assert registry.acquire(scope, "chart-b") is True


def test_different_magic_numbers_have_independent_execution_owners():
    registry = ExecutionOwnershipRegistry()

    assert registry.acquire((111, "XAUUSD", 1), "chart-a") is True
    assert registry.acquire((111, "XAUUSD", 2), "chart-b") is True


def test_duplicate_reverse_pending_keeps_tracked_ticket_and_deletes_rest():
    orders = [
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(10, "reverse", Direction.SELL, 0.06, 4436.69),
    ]

    result = normalize_pending_records(orders, tracked_ticket=12)

    assert result.keep_ticket == 12
    assert result.delete_tickets == [10]


def test_filled_tracked_reverse_deletes_all_still_active_duplicates():
    orders = [
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(10, "reverse", Direction.SELL, 0.06, 4436.69),
    ]

    result = normalize_pending_records(
        orders, tracked_ticket=9, tracked_ticket_filled=True,
    )

    assert result.keep_ticket == 9
    assert result.delete_tickets == [10, 12]


def test_duplicate_grid_pending_without_tracked_ticket_keeps_lowest_ticket():
    orders = [
        PendingRecord(22, "grid", Direction.BUY, 0.04, 4437.69),
        PendingRecord(20, "grid", Direction.BUY, 0.04, 4437.69),
    ]

    result = normalize_pending_records(orders)

    assert result.keep_ticket == 20
    assert result.delete_tickets == [22]


def test_pending_reconciliation_keeps_matching_order_and_does_not_touch_other_category():
    orders = [
        PendingRecord(10, "reverse", Direction.BUY, 0.06, 4436.69),
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(20, "grid", Direction.BUY, 0.04, 4437.69),
    ]

    result = normalize_pending_records(
        orders,
        kind="reverse",
        expected_direction=Direction.SELL,
        expected_lots=0.06,
        expected_price=4436.69,
    )

    assert result.keep_ticket == 12
    assert result.delete_tickets == [10]


def test_duplicate_base_positions_pause_new_risk_and_lot_growth():
    decision = exposure_guard(ExposureSnapshot(base_positions=2, duplicate_grid_levels=0))

    assert decision.pause_new_orders is True
    assert decision.cancel_pending is True
    assert decision.accumulate_loss_lots is False


def test_prepared_transition_reuses_existing_result_after_restart():
    transition = PreparedTransition(101, Direction.SELL, 0.26)

    result = recover_prepared_transition(
        transition, [{"direction": Direction.SELL, "lots": 0.26}],
    )

    assert result == {"phase": "complete", "market_orders": []}


def test_prepared_transition_sends_exactly_one_order_when_result_is_absent():
    transition = PreparedTransition(101, Direction.SELL, 0.26)

    result = recover_prepared_transition(transition, [])

    assert result["phase"] == "complete"
    assert result["market_orders"] == [{
        "direction": Direction.SELL, "lots": 0.26, "transition_id": 101,
    }]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_dedup_source_contract(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "AcquireExecutionOwnership" in source
    assert "ReleaseExecutionOwnership" in source
    assert "NormalizeSingleGroupPending" in source
    assert "HasDuplicateSingleGroupExposure" in source
    assert "ResumePreparedTransition" in source
    assert "ReconcileOrphanSingleGroupPending" in source
    assert '".transitionphase"' in source
    assert '".transitionid"' in source
    assert "if(!AcquireExecutionOwnership())" in source
    assert "ReleaseExecutionOwnership();" in source
    assert "NormalizeSingleGroupPending(false," in source
    assert "if(HasDuplicateSingleGroupExposure())" in source

    ensure_next = source.split("void EnsureNextPending", 1)[1].split("bool Transition", 1)[0]
    assert "if(!NormalizeSingleGroupPending(false," in ensure_next
    assert "DeleteAllPending();" not in ensure_next

    ensure_grid = source.split("void EnsureGridPending", 1)[1].split(
        "void EnsureNextPending", 1,
    )[0]
    assert "grid_filled_mask" in source
    assert "NormalizeGridPendingLevel" in source
    assert source.count("group.grid_filled_mask = 0;") >= 4
    assert "for(int level = 1; level <" in ensure_grid
    assert "g_grid_filled_levels + 1" not in ensure_grid
    multi_place = source.split("bool MultiPlaceGridPending", 1)[1].split(
        "bool MultiHandleGridFill", 1,
    )[0]
    assert "for(int level = 1; level <" in multi_place
    assert "MultiNormalizeGridPendingLevel" in multi_place
    assert "grid_filled_levels + 1" not in multi_place

    if source_name.endswith("MT5.mq5"):
        assert "retcode == TRADE_RETCODE_DONE" in source
        assert "TRADE_RETCODE_DONE_PARTIAL" in source
        assert "TRADE_RETCODE_PLACED" in source


def test_korder_type_zero_limits_parallel_initial_trigger_to_one_per_k0():
    model = dynamic_parallel_model(1, korder_type=0)
    parallel_breakout(model, 10, 600)
    assert parallel_breakout(model, 10, 600) == []
    assert len(model.groups) == 1


def test_korder_type_one_allows_parallel_initial_triggers_on_same_k0():
    model = dynamic_parallel_model(1, korder_type=1)
    parallel_breakout(model, 10, 600)
    assert parallel_breakout(model, 10, 600)[0]["kind"] == "market"
    assert len(model.groups) == 2


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_candle_distance_mode_uses_user_selected_cycle_mode(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "g_active_cycle_mode = ordertype == ORDERTYPE_FORWARD" not in source
    assert "state.cycle_mode = ordertype == ORDERTYPE_FORWARD" not in source
    if source_name.endswith("_MT5.mq5"):
        assert "g_active_cycle_mode = g_gui_applied_config.cycle_mode" in source
        assert "state.cycle_mode = g_gui_applied_config.cycle_mode" in source
    else:
        assert "g_active_cycle_mode = InpCycleMode" in source
        assert "state.cycle_mode = InpCycleMode" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_cycle_mode_parameter_describes_each_direction_sequence(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "模式一：首单多=多空空多空空；首单空=空多多空多多" in source
    assert "模式二：首单多=多空多空多多；首单空=空多空多空空" in source
    assert "模式三：首单多=多空多多空多；首单空=空多空空多空" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_pending_source_contract(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "PlaceInitialPendingPair" in source
    assert "HandleInitialPendingFill" in source
    assert "MultiPlaceInitialPendingPair" in source
    assert "MultiHandleInitialPendingFill" in source
    assert "initial_high_ticket" in source
    assert "initial_low_ticket" in source
    assert ".InitialHigh" in source
    assert ".InitialLow" in source
    assert "KORDER_ONCE_PER_BAR" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_group_take_profit_cleanup_does_not_skip_adjacent_pending_orders(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    cleanup = source.split("bool MultiDeletePending", 1)[1].split(
        "int MultiInitialPendingStatus", 1,
    )[0]

    assert "for(int index = OrdersTotal() - 1; index >= 0; index--)" in cleanup


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_take_profit_keeps_state_until_all_group_pending_orders_are_deleted(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    single_take_profit = source.split("if(TakeProfitReached", 1)[1].split(
        "if(StopReached", 1,
    )[0]
    multi_take_profit = source.split("bool MultiManageGroup", 1)[1].split(
        "const double desired_take_profit", 1,
    )[1].split(
        "desired_stop_loss", 1,
    )[0]

    assert "if(!DeleteAllPending())" in single_take_profit
    assert "if(!MultiDeletePending(group.id))" in multi_take_profit


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_group_handles_initial_fill_before_position_management(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]

    assert multi_manage.index("MultiHandleInitialPendingFill(group)") < multi_manage.index(
        "MultiFindPosition(group.id",
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_once_per_bar_reentry_cleans_stale_pending_only_on_a_new_candle(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split("void ManageMultipleCandleGroups", 1)[0]
    prepare = source.split("bool PrepareCandleOnceEntry", 1)[1].split("void Manage()", 1)[0]

    assert "current_bar_time != g_last_candle_entry_bar_time" in manage
    assert manage.index("PrepareCandleOnceEntry") < manage.index("const bool has_pending")
    assert prepare.index("DeleteAllPending()") < prepare.index("ClearState()")
    assert "MarkCandleEntryBarProcessed" in manage
    assert manage.index("ClearState();") < manage.index("MarkCandleEntryBarProcessed")


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_once_per_bar_does_not_open_another_group_until_next_candle_after_tp(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]

    assert "MarkMultiCandleTriggerBar" in multi_manage
    assert multi_manage.index("MultiClosePositions(group.id)") < multi_manage.rindex(
        "MarkMultiCandleTriggerBar"
    )

    orphan_start = "if(!has_position" if source_name.endswith(".mq5") else "if(!MultiFindPosition"
    orphan_path = multi_manage.split(orphan_start, 1)[1].split(
        "if(MultiHandleReverseFill", 1,
    )[0]
    assert "if(!MultiDeletePending(group.id))" in orphan_path
    assert orphan_path.index("MultiDeletePending(group.id)") < orphan_path.index(
        "MarkMultiCandleTriggerBar"
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_pending_cleanup_ignores_stale_initial_ticket_tracking(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    cleanup = source.split("bool DeleteAllPending", 1)[1].split(
        "int GetReversePendingStatus", 1,
    )[0]
    has_pending = source.split("bool HasOurPending", 1)[1].split(
        "void BeginFullReset", 1,
    )[0]

    assert "HasActiveInitialPending()" in has_pending
    assert "ResetInitialPendingTracking()" in cleanup
    assert cleanup.index("ResetInitialPendingTracking()") < cleanup.index("return deleted")


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_pending_pair_preserves_oco_cancel_on_fill(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    fill_handler = source.split("bool HandleInitialPendingFill", 1)[1].split(
        "bool PlaceNextPending", 1,
    )[0]
    multi_fill_handler = source.split("bool MultiHandleInitialPendingFill", 1)[1].split(
        "bool MultiPlaceReversePending", 1,
    )[0]

    assert "Initial OCO delete" in fill_handler or "OrderDelete(other_ticket" in fill_handler
    assert "Multi initial OCO delete" in multi_fill_handler or "OrderDelete(other_ticket" in multi_fill_handler
    assert "FindPositionByPendingOrder(filled_ticket" in fill_handler or "FindPositionByTicket(filled_ticket" in fill_handler
    assert "FindPositionByPendingOrder(filled_ticket" in multi_fill_handler or "FindPositionByTicket(filled_ticket" in multi_fill_handler


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_once_per_bar_cleanup_runs_before_initial_fill_short_circuit(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split(
        "void ManageMultipleCandleGroups", 1,
    )[0]
    prepare = source.split("bool PrepareCandleOnceEntry", 1)[1].split(
        "void Manage()", 1,
    )[0]

    assert manage.index("PrepareCandleOnceEntry") < manage.index("HandleInitialPendingFill")
    assert "HasOurPosition()" in prepare


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_fill_requires_a_real_filled_side_before_promoting_position(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    handler = source.split("bool HandleInitialPendingFill", 1)[1].split(
        "bool PlaceNextPending", 1,
    )[0]

    assert "const bool high_filled" in handler
    assert "const bool low_filled" in handler
    assert "if(high_filled || low_filled)" in handler
    assert "if(high_status == REVERSE_PENDING_UNKNOWN" in handler


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_mt5_and_mt4_have_a_fast_initial_oco_event_path(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "void OnTimer()" in source
    if source_name.endswith(".mq5"):
        assert "void OnTradeTransaction" in source


def test_gui_draft_does_not_change_applied_config_until_apply():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.edit("initial_lots", 0.05)

    assert model.applied["initial_lots"] == 0.01
    assert model.draft["initial_lots"] == 0.05
    assert model.has_unapplied_changes is True

    result = model.apply()

    assert result.ok is True
    assert model.applied["initial_lots"] == 0.05
    assert model.has_unapplied_changes is False

    model.edit("initial_lots", 0.10)

    assert model.applied["initial_lots"] == 0.05
    assert model.draft["initial_lots"] == 0.10
    assert model.has_unapplied_changes is True


def test_gui_pause_and_resume_only_controls_new_initial_entry():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})
    applied_before = dict(model.applied)
    draft_before = dict(model.draft)
    unapplied_before = model.has_unapplied_changes

    model.pause_new_initial_entry()

    assert model.paused_new_initial_entry is True
    assert model.strategy_management_enabled is True
    assert model.pending_orders_are_preserved is True
    assert model.applied == applied_before
    assert model.draft == draft_before
    assert model.has_unapplied_changes is unapplied_before

    model.resume_new_initial_entry()

    assert model.paused_new_initial_entry is False
    assert model.should_force_market_order is False


def test_gui_close_all_requires_confirmation_and_reports_incomplete_cleanup():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    request = model.request_close_all()
    result = model.confirm_close_all(close_ok=False, delete_ok=True)

    assert request.requires_confirmation is True
    assert result.status == "cleanup_incomplete"


def test_gui_close_all_reports_incomplete_cleanup_when_delete_fails():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.request_close_all()

    assert model.confirm_close_all(close_ok=True, delete_ok=False).status == "cleanup_incomplete"


def test_gui_close_all_reports_closed_when_both_cleanup_operations_succeed():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.request_close_all()

    assert model.confirm_close_all(close_ok=True, delete_ok=True).status == "closed"


def test_gui_close_all_cannot_confirm_without_a_pending_request():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})
    state_before = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }

    result = model.confirm_close_all(close_ok=True, delete_ok=True)

    assert result.status == "confirmation_required"
    assert model.applied == state_before["applied"]
    assert model.draft == state_before["draft"]
    assert model.has_unapplied_changes is state_before["has_unapplied_changes"]
    assert model.close_all_requested is state_before["close_all_requested"]
    assert model.cleanup_state == state_before["cleanup_state"]

    state_before_request = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }
    model.request_close_all()
    state_before_cancel = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }
    assert state_before_cancel["close_all_requested"] is True

    cancel_result = model.cancel_close_all()

    assert cancel_result.status == "cancelled"
    assert model.applied == state_before_cancel["applied"]
    assert model.draft == state_before_cancel["draft"]
    assert model.has_unapplied_changes is state_before_cancel["has_unapplied_changes"]
    assert model.cleanup_state == state_before_cancel["cleanup_state"]
    assert model.close_all_requested is state_before_request["close_all_requested"]
