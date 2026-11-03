# -*- coding: utf-8 -*-
# 直接构造 DSTModTool 的 json 数据结构打包动画（绕开 scml.exe / scml 中间层）。
# 坐标约定完全对齐原版数据（用 yoth_knightshrine 反解结果核对过）：
#   * build/anim 帧的 y 轴：负值 = 向上（地面上方）
#   * build 帧的 x/y = 内容画布中心相对原点的偏移，verts 由 atlas_images 生成
#   * 帧率 30
# 用法：python pack_anim.py   （输出 landshrine/anim/landshrine.zip）
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.environ.get("DST_MOD_TOOL") or os.path.join(ROOT, "tools", "DSTModTool")
sys.path.insert(0, TOOL)

from ds_file.anim import DSAnim
from klei.matrix3 import create_trans_rot_scale_pivot_matrix
import math

BUILD_NAME = "landshrine"
SYMBOL = "shrine"
W, H = 632, 600           # 统一画布尺寸
OUTPUT = os.path.join(ROOT, "landshrine", "anim")

def frame_bbox(scale=1.0):
    # 内容立在原点上、向上延伸：中心在 (0, -H*scale/2)
    return {"x": 0.0, "y": -H * scale / 2, "w": W * scale, "h": H * scale}

def element(frame_num, angle_deg=0.0, scale=1.0):
    m = create_trans_rot_scale_pivot_matrix(
        (0, 0), math.radians(angle_deg), (scale, scale), (0, 0)).matrix
    return {
        "name": SYMBOL, "frame": frame_num, "layername": SYMBOL,
        "m_a": m[0][0], "m_b": m[1][0], "m_c": m[0][1], "m_d": m[1][1],
        "m_tx": m[0][2], "m_ty": m[1][2], "z_index": 0,
    }

def Frame(frame_num, angle_deg=0.0, scale=1.0):
    f = frame_bbox(scale)
    f["elements"] = [element(frame_num, angle_deg, scale)]
    return f

# 动画定义（帧率 30；帧序列与 prefab 代码的动画名契约一致）
anims = {
    "idle_off": [Frame(0)],
    "idle_on":  [Frame(1)],
    "place":    [Frame(0, scale=0.75), Frame(0)],
    "activate": [Frame(0), Frame(0), Frame(1), Frame(1)],
    "hit_off":  [Frame(0), Frame(0, angle_deg=-4), Frame(0, angle_deg=4), Frame(0)],
}

def main():
    build_data = {
        "type": "Build", "version": 6, "name": BUILD_NAME, "scale": 1,
        "Symbol": {SYMBOL: [
            {"framenum": 0, "duration": 1, "x": 0, "y": -H / 2, "w": W, "h": H},
            {"framenum": 1, "duration": 1, "x": 0, "y": -H / 2, "w": W, "h": H},
        ]},
    }
    symbols_images = {
        f"{SYMBOL}-0": os.path.join(os.path.dirname(__file__), "..", "landshrine", "exported", "landshrine", "shrine", "shrine_off.png"),
        f"{SYMBOL}-1": os.path.join(os.path.dirname(__file__), "..", "landshrine", "exported", "landshrine", "shrine", "shrine_on.png"),
    }
    anim_data = {
        "type": "Anim", "version": 4,
        "banks": {BUILD_NAME: {name: {"framerate": 30, "frames": frames} for name, frames in anims.items()}},
    }

    with DSAnim(anim_data) as anim:
        anim.parse_file(build_data, symbols_images)
        anim.save_bin(OUTPUT)
    print("已打包:", os.path.join(OUTPUT, BUILD_NAME + ".zip"))

if __name__ == "__main__":
    main()
