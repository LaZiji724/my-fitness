// 由设计稿 Stats 画布里的人体示意图转成的模板：{{名称}} 在运行时替换成颜色。
// 区域键：body 非肌肉部位；其余对应肌肉分组（见 muscle_figure.dart）。
library;

const frontFigureTemplate = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 250">
<g stroke="{{stroke}}" stroke-width="1.2" stroke-linejoin="round">
<ellipse cx="60" cy="18" rx="11" ry="13" fill="{{body}}"/>
<rect x="54" y="29" width="12" height="9" rx="3" fill="{{body}}"/>
<path d="M47 40 Q60 34 73 40 L68 45 Q60 41 52 45 Z" fill="{{traps}}"/>
<ellipse cx="38" cy="51" rx="10" ry="11" fill="{{shoulders}}"/>
<ellipse cx="82" cy="51" rx="10" ry="11" fill="{{shoulders}}"/>
<path d="M59 44 L59 71 Q50 75 42 69 Q37 60 44 50 Q50 45 59 44 Z" fill="{{chest}}"/>
<path d="M61 44 L61 71 Q70 75 78 69 Q83 60 76 50 Q70 45 61 44 Z" fill="{{chest}}"/>
<ellipse cx="31" cy="76" rx="6.5" ry="13" transform="rotate(12 31 76)" fill="{{biceps}}"/>
<ellipse cx="89" cy="76" rx="6.5" ry="13" transform="rotate(-12 89 76)" fill="{{biceps}}"/>
<ellipse cx="25" cy="104" rx="5.5" ry="14" transform="rotate(14 25 104)" fill="{{forearms}}"/>
<ellipse cx="95" cy="104" rx="5.5" ry="14" transform="rotate(-14 95 104)" fill="{{forearms}}"/>
<circle cx="20" cy="122" r="4.5" fill="{{body}}"/>
<circle cx="100" cy="122" r="4.5" fill="{{body}}"/>
<path d="M49 75 Q42 92 45 117 Q48 119 50.5 117 L50.5 76 Z" fill="{{abs}}"/>
<path d="M71 75 Q78 92 75 117 Q72 119 69.5 117 L69.5 76 Z" fill="{{abs}}"/>
<rect x="51.5" y="74" width="17" height="45" rx="6" fill="{{abs}}"/>
<path d="M60 76 V117 M52 86 H68 M52 97 H68 M52 108 H68" fill="none"/>
<path d="M46 119 L74 119 L71 132 L49 132 Z" fill="{{body}}"/>
<path d="M46 128 Q39 152 44 179 Q48 187 54.5 182 Q58.5 160 58.5 134 Q52 127 46 128 Z" fill="{{quadriceps}}"/>
<path d="M74 128 Q81 152 76 179 Q72 187 65.5 182 Q61.5 160 61.5 134 Q68 127 74 128 Z" fill="{{quadriceps}}"/>
<circle cx="50" cy="190" r="5" fill="{{body}}"/>
<circle cx="70" cy="190" r="5" fill="{{body}}"/>
<ellipse cx="49" cy="214" rx="6" ry="18" fill="{{calves}}"/>
<ellipse cx="71" cy="214" rx="6" ry="18" fill="{{calves}}"/>
<ellipse cx="48" cy="238" rx="7" ry="4.5" fill="{{body}}"/>
<ellipse cx="72" cy="238" rx="7" ry="4.5" fill="{{body}}"/>
</g>
</svg>''';

const backFigureTemplate = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 250">
<g stroke="{{stroke}}" stroke-width="1.2" stroke-linejoin="round">
<ellipse cx="60" cy="18" rx="11" ry="13" fill="{{body}}"/>
<rect x="54" y="29" width="12" height="9" rx="3" fill="{{body}}"/>
<path d="M60 34 L75 44 L60 66 L45 44 Z" fill="{{traps}}"/>
<ellipse cx="38" cy="51" rx="10" ry="11" fill="{{shoulders}}"/>
<ellipse cx="82" cy="51" rx="10" ry="11" fill="{{shoulders}}"/>
<path d="M47 54 Q41 72 50 98 L58.5 99 L58.5 66 L52 56 Z" fill="{{lats}}"/>
<path d="M73 54 Q79 72 70 98 L61.5 99 L61.5 66 L68 56 Z" fill="{{lats}}"/>
<ellipse cx="31" cy="76" rx="6.5" ry="13" transform="rotate(12 31 76)" fill="{{triceps}}"/>
<ellipse cx="89" cy="76" rx="6.5" ry="13" transform="rotate(-12 89 76)" fill="{{triceps}}"/>
<ellipse cx="25" cy="104" rx="5.5" ry="14" transform="rotate(14 25 104)" fill="{{forearms}}"/>
<ellipse cx="95" cy="104" rx="5.5" ry="14" transform="rotate(-14 95 104)" fill="{{forearms}}"/>
<circle cx="20" cy="122" r="4.5" fill="{{body}}"/>
<circle cx="100" cy="122" r="4.5" fill="{{body}}"/>
<rect x="51.5" y="99" width="17" height="20" rx="5" fill="{{lower_back}}"/>
<ellipse cx="52" cy="131" rx="9" ry="11" fill="{{glutes}}"/>
<ellipse cx="68" cy="131" rx="9" ry="11" fill="{{glutes}}"/>
<path d="M44.5 142 Q41 162 46 181 Q50 187 55 182 Q58.5 162 57.5 143 Z" fill="{{hamstrings}}"/>
<path d="M75.5 142 Q79 162 74 181 Q70 187 65 182 Q61.5 162 62.5 143 Z" fill="{{hamstrings}}"/>
<circle cx="50" cy="190" r="5" fill="{{body}}"/>
<circle cx="70" cy="190" r="5" fill="{{body}}"/>
<ellipse cx="49" cy="212" rx="7" ry="17" fill="{{calves}}"/>
<ellipse cx="71" cy="212" rx="7" ry="17" fill="{{calves}}"/>
<ellipse cx="48" cy="238" rx="7" ry="4.5" fill="{{body}}"/>
<ellipse cx="72" cy="238" rx="7" ry="4.5" fill="{{body}}"/>
</g>
</svg>''';
