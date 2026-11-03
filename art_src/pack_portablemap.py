# -*- coding: utf-8 -*-
# 打包随身地图的世界模型动画（单帧 idle，卷轴居中，物品以原点为中心渲染）
# 坐标约定与 pack_anim.py 相同（负 y = 地面上方；物品居中所以 y=0）
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.environ.get("DST_MOD_TOOL") or os.path.join(ROOT, "tools", "DSTModTool")
sys.path.insert(0, TOOL)

from ds_file.anim import DSAnim

BUILD_NAME = "landshrine_portablemap"
SYMBOL = BUILD_NAME
W, H = 192, 192
HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(HERE, "..", "landshrine", "anim")

def main():
    build_data = {
        "type": "Build", "version": 6, "name": BUILD_NAME, "scale": 1,
        "Symbol": {SYMBOL: [
            {"framenum": 0, "duration": 1, "x": 0, "y": 0, "w": W, "h": H},
        ]},
    }
    symbols_images = {
        f"{SYMBOL}-0": os.path.join(HERE, "..", "landshrine", "exported", BUILD_NAME, SYMBOL, f"{SYMBOL}.png"),
    }
    anim_data = {
        "type": "Anim", "version": 4,
        "banks": {BUILD_NAME: {"idle": {"framerate": 30, "frames": [
            {"x": 0, "y": 0, "w": W, "h": H,
             "elements": [{"name": SYMBOL, "frame": 0, "layername": SYMBOL,
                           "m_a": 1, "m_b": 0, "m_c": 0, "m_d": 1, "m_tx": 0, "m_ty": 0, "z_index": 0}]},
        ]}}},
    }

    with DSAnim(anim_data) as anim:
        anim.parse_file(build_data, symbols_images)
        anim.save_bin(OUTPUT)
    print("已打包:", os.path.join(OUTPUT, BUILD_NAME + ".zip"))

if __name__ == "__main__":
    main()
