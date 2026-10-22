from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "FixedDistance": "FIXED_DISTANCE",
    "CandleHeight": "CANDLE_HEIGHT",
    "AverageCandleHeight": "AVERAGE_CANDLE_HEIGHT",
    "LongCandle": "LONG_CANDLE",
    "BollingerRange": "BOLLINGER_RANGE",
    "ZigZagSwing": "ZIGZAG_SWING",
    "BoxHeight": "BOX_HEIGHT",
    "BoxBreakout": "BOX_BREAKOUT",
    "AverageDoubleCandle": "AVERAGE_DOUBLE_CANDLE",
    "BollingerExpansion": "BOLLINGER_EXPANSION",
}
COMMON_INPUTS = {
    "循环模式",
    "篮子数量",
    "首单手数",
    "首单手数倍数",
    "止损首单类型",
    "首单类型2倍数",
    "止损首单固定手数",
    "最大反手次数",
    "最大首单点差",
    "止盈移动模式",
    "网格数量",
    "有利方向加单",
    "动态止损",
    "网格手数倍数",
    "订单识别编号",
    "订单注释",
    "开始时间",
    "结束时间",
    "时段2开始时间",
    "时段2结束时间",
    "时段3开始时间",
    "时段3结束时间",
}
PROFILE_INPUTS = {
    "FixedDistance": {
        "首单方向", "首单方向确定方式", "布林带周期", "布林带标准差",
        "固定止损距离", "固定止盈距离",
    },
    "CandleHeight": {
        "开单方式", "K线开单模式", "K线多组", "K线最小高度", "K线最大高度",
    },
    "AverageCandleHeight": {
        "首单方向", "首单方向确定方式", "布林带周期", "布林带标准差",
        "平均K线根数", "平均止损倍数", "平均止盈倍数",
    },
    "LongCandle": {"固定止损距离", "固定止盈距离"},
    "BollingerExpansion": {"首单方向", "首单方向确定方式", "布林带周期", "布林带标准差", "带宽比较K线根数", "带宽触发倍数", "带宽距离模式", "带宽距离百分比", "固定止损距离", "固定止盈距离"},
    "AverageDoubleCandle": {"开单方式", "均值比较K线根数", "均值触发倍数", "信号K线距离百分比"},
    "BollingerRange": {
        "布林带周期", "布林带标准差", "开单方式", "布林带止损百分比",
        "布林带盈亏比", "布林带最小止损距离", "布林带最大止损距离",
    },
    "ZigZagSwing": {
        "ZigZag深度", "ZigZag偏差", "ZigZag回退", "ZigZag距离最小值",
        "ZigZag距离最大值", "ZigZag止损百分比", "ZigZag止盈倍数", "开单方式",
    },
    "BoxHeight": {
        "箱体时间模式", "箱体回看小时数", "箱体开始时间", "箱体结束时间",
        "箱体最小高度", "箱体最大高度", "首单方向", "首单方向确定方式",
        "布林带周期", "布林带标准差",
    },
    "BoxBreakout": {
        "箱体识别周期", "箱体观察窗口K线数", "箱体ATR周期", "箱体触碰ATR倍数",
        "箱体上沿最少触碰", "箱体下沿最少触碰", "箱体最少完整往返",
        "箱体同侧触碰间隔", "箱体突破最小宽度", "箱体突破最大宽度",
        "箱体突破缓冲ATR倍数", "开单方式",
    },
}


def _expanded_source(path: Path, macros=None):
    macros = set() if macros is None else macros
    output = []
    conditions = []
    active = True
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        directive = re.match(r"^\s*#(ifdef|ifndef|else|endif|define|undef|include)\b\s*(.*)$", line)
        if directive:
            kind, argument = directive.groups()
            if kind in {"ifdef", "ifndef"}:
                parent_active = active
                defined = argument.strip() in macros
                condition = defined if kind == "ifdef" else not defined
                conditions.append((parent_active, condition))
                active = parent_active and condition
            elif kind == "else":
                parent_active, condition = conditions[-1]
                active = parent_active and not condition
                conditions[-1] = (parent_active, not condition)
            elif kind == "endif":
                parent_active, _ = conditions.pop()
                active = parent_active
            elif active and kind == "define":
                macros.add(argument.split()[0])
                output.append(line)
            elif active and kind == "undef":
                macros.discard(argument.split()[0])
            elif active and kind == "include":
                include = re.fullmatch(r'"([^"]+)"', argument.strip())
                if include:
                    child = path.parent / include.group(1)
                    assert child.is_file(), f"missing MQL include: {child}"
                    output.append(_expanded_source(child, macros))
            continue
        if active:
            output.append(line)
    assert not conditions, f"unclosed MQL conditional in {path}"
    return "\n".join(output)


def _input_names(source: str):
    return {
        match.group(1)
        for match in re.finditer(
            r"^\s*input\s+(?!group\b).+?\s+([\w\u0080-\uffff]+)\s*=",
            source,
            re.MULTILINE,
        )
    }


def _wrapper(name: str, platform: str):
    extension = ".mq4" if platform == "MT4" else ".mq5"
    return ROOT / f"NoMatterRiseFall_{name}_{platform}{extension}"


def test_each_profile_has_one_fixed_identity():
    for name, identity in PROFILES.items():
        for platform, extension in (("MT4", ".mq4"), ("MT5", ".mq5")):
            wrapper = ROOT / f"NoMatterRiseFall_{name}_{platform}{extension}"
            assert wrapper.is_file(), f"missing fixed-profile entry point: {wrapper.name}"
            source = wrapper.read_text(encoding="utf-8")
            definitions = re.findall(r"^\s*#define\s+(NMR_PROFILE_[A-Z_]+)\s*$", source, re.MULTILINE)
            assert definitions == [f"NMR_PROFILE_{identity}"]
            assert not re.search(r"^\s*input\s+DistanceMode\b", source, re.MULTILINE)


def test_each_profile_exposes_only_common_and_mode_inputs():
    for name in PROFILES:
        for platform in ("MT4", "MT5"):
            inputs = _input_names(_expanded_source(_wrapper(name, platform)))
            expected = COMMON_INPUTS | PROFILE_INPUTS[name]
            if platform == "MT5":
                expected.add("v_enable")
            assert inputs == expected, f"{name} {platform} input mismatch: {inputs ^ expected}"


def test_new_profile_magic_defaults_are_unique():
    defaults = []
    for name in PROFILES:
        for platform in ("MT4", "MT5"):
            wrapper = _wrapper(name, platform)
            source = _expanded_source(wrapper)
            assert re.search(r"^\s*input\s+(?:int|ulong)\s+订单识别编号\s*=\s*NMR_MAGIC_DEFAULT\s*;", source, re.MULTILINE)
            match = re.search(r"^\s*#define\s+NMR_MAGIC_DEFAULT\s+(\d+)\s*$", wrapper.read_text(encoding="utf-8-sig"), re.MULTILINE)
            assert match, f"missing {name} {platform} Magic default"
            defaults.append(int(match.group(1)))
    assert len(set(defaults)) == 20
    assert all(0 < value <= 2_147_483_647 for value in defaults)


def test_legacy_sources_keep_all_mode_inputs_and_magic():
    for platform, extension in (("MT4", ".mq4"), ("MT5", ".mq5")):
        source = (ROOT / f"NoMatterRiseFall_{platform}{extension}").read_text(encoding="utf-8-sig")
        assert re.search(r"^\s*input\s+DistanceMode\s+距离模式\s*=", source, re.MULTILINE)
        assert re.search(r"订单识别编号\s*=\s*20260830\s*;", source)


def test_order_state_is_profile_scoped_and_magic_reservation_is_shared():
    for name in PROFILES:
        for platform in ("MT4", "MT5"):
            source = _expanded_source(_wrapper(name, platform))
            prefix_match = re.search(r"string StatePrefix\(\)\s*\{([^}]*)\}", source, re.DOTALL)
            assert prefix_match and "NMR_FIXED_PROFILE_ID" in prefix_match.group(1)
            assert '".v1"' in prefix_match.group(1)
            lock_match = re.search(r"string ExecutionLockFileName\(\)\s*\{([^}]*)\}", source, re.DOTALL)
            lock_magic = "InpMagicNumber" if platform == "MT4" else "g_gui_applied_config.magic_number"
            assert lock_match and lock_magic in lock_match.group(1)
            assert "NMR_FIXED_PROFILE_ID" not in lock_match.group(1)
            if platform == "MT4":
                on_init = re.search(r"int OnInit\(\)\s*\{(.*?)\n  \}", source, re.DOTALL)
                assert on_init and "ValidateFixedProfileStartupState" in on_init.group(1)
            else:
                validator = re.search(
                    r"bool ValidatePersistedConfigForMagic\([^)]*\)\s*\{(.*?)\n  \}",
                    source,
                    re.DOTALL,
                )
                assert validator and "unowned" in validator.group(1).lower()
                assert "NMR_FIXED_PROFILE_ID" in source[source.index("bool RememberManagedScope("):]


def test_mt5_panel_shows_fixed_profile_without_a_mode_selector():
    for name in PROFILES:
        source = _expanded_source(_wrapper(name, "MT5"))
        render = source[source.index("bool GuiRender()"):]
        assert 'GuiRenderEnumField("distance_mode"' not in render
        assert 'GuiRenderReadOnlyField("overview.distance_mode"' not in render
        assert "NMR_PROFILE_DISPLAY_NAME" in source
        assert '"EA模式"' in source


def test_mt5_parameter_pages_render_only_profile_fields():
    distance_inputs = {
        "FixedDistance": {"stop_loss_distance_points", "take_profit_distance_points"},
        "CandleHeight": {"candle_min_range_points", "candle_max_range_points"},
        "AverageCandleHeight": {
            "average_candle_count", "average_stop_multiplier", "average_take_profit_multiplier"
        },
        "LongCandle": {"stop_loss_distance_points", "take_profit_distance_points"},
        "AverageDoubleCandle": {"double_candle_count", "double_candle_distance_percent", "double_candle_trigger_multiplier"},
        "BollingerExpansion": {"boll_exp_count", "boll_exp_distance_mode", "boll_exp_percent", "boll_exp_trigger_multiplier", "stop_loss_distance_points", "take_profit_distance_points"},
        "BollingerRange": {
            "bollinger_stop_percent", "bollinger_reward_risk_ratio",
            "bollinger_min_stop_points", "bollinger_max_stop_points",
        },
        "ZigZagSwing": {
            "zigzag_depth", "zigzag_deviation", "zigzag_backstep", "zigzag_min_points",
            "zigzag_max_points", "zigzag_stop_percent", "zigzag_take_profit_multiplier",
        },
        "BoxHeight": {
            "box_range_time_mode", "box_range_lookback_hours", "box_range_start_time",
            "box_range_end_time", "box_range_min_points", "box_range_max_points",
        },
        "BoxBreakout": {
            "box_breakout_timeframe", "box_breakout_lookback_bars", "box_breakout_atr_period",
            "box_breakout_touch_atr_multiplier", "box_breakout_min_upper_touches",
            "box_breakout_min_lower_touches", "box_breakout_min_round_trips",
            "box_breakout_min_touch_spacing_bars", "box_breakout_min_width_points",
            "box_breakout_max_width_points", "box_breakout_buffer_atr_multiplier",
        },
    }
    shared_opening = {
        "cycle_mode", "initial_lots", "initial_lots_multiplier", "first_order_lot_type",
        "first_order_mult", "stop_first_order_lots",
    }
    for name in PROFILES:
        source = _expanded_source(_wrapper(name, "MT5"))
        gui_render = source[source.index("bool GuiRenderContent()\n  {"):]
        distance_start = re.search(
            r'else if\(g_gui_page == GUI_PAGE_DISTANCE\)\s*\{\s*const int left_x = x \+ GUI_CONTENT_PADDING',
            gui_render,
        ).start()
        distance_end = re.search(
            r'else if\(g_gui_page == GUI_PAGE_GRID\)\s*\{\s*const int left_x = x \+ GUI_CONTENT_PADDING',
            gui_render[distance_start:],
        ).start() + distance_start
        distance_page = gui_render[distance_start:distance_end]
        distance_keys = set(re.findall(r'GuiRender(?:EditableDropdownField|EnumField)\("([^"]+)"', distance_page))
        assert distance_keys == distance_inputs[name] | {"take_profit_mode"}, name

        opening_start = re.search(
            r'else if\(g_gui_page == GUI_PAGE_OPENING\)\s*\{\s*const int left_x = x \+ GUI_CONTENT_PADDING',
            gui_render,
        ).start()
        opening_end = distance_start
        opening_page = gui_render[opening_start:opening_end]
        opening_keys = set(re.findall(r'GuiRender(?:EditableDropdownField|EnumField)\("([^"]+)"', opening_page))
        expected_opening = set(shared_opening)
        if name in {"FixedDistance", "AverageCandleHeight", "BoxHeight", "BollingerExpansion"}:
            expected_opening |= {"first_direction", "first_direction_mode"}
        if name in {"CandleHeight", "BollingerRange", "ZigZagSwing", "BoxBreakout", "AverageDoubleCandle"}:
            expected_opening.add("order_type")
        if name == "CandleHeight":
            expected_opening |= {"candle_order_mode", "candle_enable_multiple"}
        if name in {"FixedDistance", "AverageCandleHeight", "BollingerRange", "BoxHeight", "BollingerExpansion"}:
            expected_opening |= {"bollinger_period", "bollinger_deviation"}
        assert opening_keys == expected_opening, name


def test_mt5_state_owner_and_unowned_orders_are_validated_before_loading():
    source = _expanded_source(_wrapper("FixedDistance", "MT5"))
    validator = re.search(
        r"bool ValidatePersistedConfigForMagic\([^)]*\)\s*\{(.*?)\n  \}",
        source,
        re.DOTALL,
    )
    assert validator
    body = validator.group(1)
    assert "owner.profile" in body and "owner.schema" in body
    assert "HasManagedExposureForMagic" in body and "unowned" in body.lower()
    assert "StateScopePrefix" in body and "HasForeignProfileStateForMagic" in body
    assert "unowned" in body.lower(), "legacy or foreign profile state must not be silently adopted"
    remember = source[source.index("bool RememberManagedScope(") :]
    assert "1000.0 + NMR_FIXED_PROFILE_ID" in remember
    assert "belongs to another fixed profile" in remember.lower()
