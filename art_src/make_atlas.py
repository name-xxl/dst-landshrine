# -*- coding: utf-8 -*-
# 确定性图标图集打包：一行排开 → 生成 .tex（经 ktech png_to_tex）+ .xml
# 用法: python make_atlas.py <输出tex路径> <画布边长> <png1> <png2> ...
#   png 会被缩放到 <画布边长> 见方后横向平铺；画布宽 = pow2(边长*数量)，高 = 边长
import sys, os
import math
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.environ.get("DST_MOD_TOOL") or os.path.join(ROOT, "tools", "DSTModTool")
sys.path.insert(0, TOOL)
from ktech.texture_converter import png_to_tex

def pow2(n):
    return 1 << (n - 1).bit_length()

def main():
    out_tex, side, *pngs = sys.argv[1:]
    side = int(side)
    canvas_w = pow2(side * len(pngs))
    canvas = Image.new("RGBA", (canvas_w, side), (0, 0, 0, 0))
    elements = []
    for i, p in enumerate(pngs):
        im = Image.open(p).convert("RGBA").resize((side, side), Image.LANCZOS)
        x = i * side
        canvas.alpha_composite(im, (x, 0))
        name = os.path.splitext(os.path.basename(p))[0] + ".tex"
        elements.append((name, x / canvas_w, (x + side) / canvas_w))
        print(f"  + {name} @ x={x}")

    tex = os.path.abspath(out_tex)
    tmp_png = tex.replace(".tex", ".png")
    canvas.save(tmp_png)
    png_to_tex(tmp_png, tex)
    os.remove(tmp_png)

    xml = ['<Atlas>', '\t<Texture filename="' + os.path.basename(tex) + '" />', '\t<Elements>']
    for name, u1, u2 in elements:
        xml.append(f'\t\t<Element name="{name}" u1="{u1:.6f}" v1="0.000000" u2="{u2:.6f}" v2="1.000000" />')
    xml += ['\t</Elements>', '</Atlas>']
    with open(tex.replace(".tex", ".xml"), "w", encoding="utf-8") as f:
        f.write("\n".join(xml) + "\n")
    print(f"已输出 {tex} + .xml（画布 {canvas_w}x{side}）")

if __name__ == "__main__":
    main()
