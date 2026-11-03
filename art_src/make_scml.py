# -*- coding: utf-8 -*-
# 生成 landshrine.scml（Spriter 工程）：
#   单一部件、静态姿态 + 简单变换，5 个动画，名字与 prefab 代码的契约一致：
#     place(落成) idle_off(未激活循环) activate(上香激活) idle_on(已激活循环) hit_off(被敲击)
#   entity 名 = bank 名，scml 文件名 = build 名（autocompiler 约定）
# 注意：scml.exe 把 <key time> 直接当帧号用（numframes == time 值），编译链固定 framerate=40。
# Spriter 导出惯例：循环动画省略 looping 属性，只有非循环才写 looping="false"。
import sys

FILES = [
    ("shrine/shrine_off.png", 316, 300),
    ("shrine/shrine_on.png", 316, 300),
]
PIVOT_X, PIVOT_Y = 0.5, 1.0   # 底部中心为锚点（地面原点）

# (动画名, looping, [(time_ms, file_id, angle, scale_x, scale_y, alpha, y)])
# 打包用 DSTModTool（convert.py 同款转换器）：要求关键帧时间落在 30fps 网格
# （33ms 的倍数），time 单位为毫秒。idle 恢复为真静态单帧。
ANIMS = [
    ("idle_off", True, [
        (0, 0, 0, 1.0, 1.0, 1.0, 0),
    ]),
    ("idle_on", True, [
        (0, 1, 0, 1.0, 1.0, 1.0, 0),
    ]),
    ("place", False, [
        (0,   0, 0, 0.75, 0.75, 0.5, 0),
        (198, 0, 0, 1.0,  1.0,  1.0, 0),
    ]),
    ("activate", False, [
        (0,   0, 0, 1.0, 1.0, 1.0, 0),
        (99,  0, 0, 1.0, 1.0, 0.0, 0),
        (198, 1, 0, 1.0, 1.0, 0.0, 0),
        (297, 1, 0, 1.0, 1.0, 1.0, 0),
    ]),
    ("hit_off", False, [
        (0,   0, 0,  1.0, 1.0, 1.0, 0),
        (66,  0, -4, 1.0, 1.0, 1.0, 0),
        (132, 0, 4,  1.0, 1.0, 1.0, 0),
        (198, 0, 0,  1.0, 1.0, 1.0, 0),
    ]),
]


def main():
    out = ['<?xml version="1.0" encoding="UTF-8"?>']
    out.append('<spriter_data generator="BrashMonkey Spriter" generator_version="b5" scml_version="1.0">')
    out.append('\t<folder id="0" name="shrine">')
    for i, (name, w, h) in enumerate(FILES):
        out.append(f'\t\t<file id="{i}" name="{name}" width="{w}" height="{h}" '
                   f'pivot_x="{PIVOT_X}" pivot_y="{PIVOT_Y}"/>')
    out.append('\t</folder>')
    out.append('\t<entity id="0" name="landshrine">')

    for ai, (anim_name, looping, keys) in enumerate(ANIMS):
        length = max(k[0] for k in keys)
        loop_attr = ' looping="false"'  # 实验证明：省略该属性的动画会被 scml.exe 静默丢弃
        out.append(f'\t\t<animation id="{ai}" name="{anim_name}" length="{length}"{loop_attr}>')
        out.append('\t\t\t<mainline>')
        for ki, (t, fid, angle, sx, sy, alpha, y) in enumerate(keys):
            out.append(f'\t\t\t\t<key id="{ki}" time="{t}">')
            out.append(f'\t\t\t\t\t<object_ref abs_a="{alpha}" abs_angle="{angle}" '
                       f'abs_pivot_x="{PIVOT_X}" abs_pivot_y="{PIVOT_Y}" abs_scale_x="{sx}" abs_scale_y="{sy}" '
                       f'abs_x="0" abs_y="{y}" file="{fid}" folder="0" id="{ki}" key="{ki}" '
                       f'name="{anim_name}" timeline="0" z_index="0"/>')
            out.append('\t\t\t\t</key>')
        out.append('\t\t\t</mainline>')
        out.append('\t\t\t<timeline id="0" name="shrine">')
        for ki, (t, fid, angle, sx, sy, alpha, y) in enumerate(keys):
            out.append(f'\t\t\t\t<key id="{ki}" spin="0" time="{t}">')
            out.append(f'\t\t\t\t\t<object angle="{angle}" a="{alpha}" file="{fid}" folder="0" '
                       f'pivot_x="{PIVOT_X}" pivot_y="{PIVOT_Y}" scale_x="{sx}" scale_y="{sy}" x="0" y="{y}"/>')
            out.append('\t\t\t\t</key>')
        out.append('\t\t\t</timeline>')
        out.append('\t\t</animation>')

    out.append('\t</entity>')
    out.append('</spriter_data>')

    with open("landshrine.scml", "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("已生成 landshrine.scml,", len(ANIMS), "个动画:", ", ".join(a[0] for a in ANIMS))


if __name__ == "__main__":
    main()
