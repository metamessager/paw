#!/usr/bin/env python3
"""
生成 AI Agent Hub 应用图标
使用 Pillow (PIL) 库创建渐变背景和图标元素
"""

from PIL import Image, ImageDraw, ImageFont
import math

def create_gradient_background(size, color1, color2):
    """创建渐变背景"""
    image = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(image)

    # 从左上到右下的对角渐变
    for y in range(size):
        for x in range(size):
            # 计算渐变位置 (0.0 到 1.0)
            position = (x + y) / (size * 2)

            # 插值计算颜色
            r = int(color1[0] + (color2[0] - color1[0]) * position)
            g = int(color1[1] + (color2[1] - color1[1]) * position)
            b = int(color1[2] + (color2[2] - color1[2]) * position)

            draw.point((x, y), fill=(r, g, b, 255))

    return image

def draw_rounded_rectangle(draw, coords, radius, fill):
    """绘制圆角矩形"""
    x1, y1, x2, y2 = coords
    draw.rectangle([x1 + radius, y1, x2 - radius, y2], fill=fill)
    draw.rectangle([x1, y1 + radius, x2, y2 - radius], fill=fill)

    # 四个圆角
    draw.pieslice([x1, y1, x1 + radius * 2, y1 + radius * 2], 180, 270, fill=fill)
    draw.pieslice([x2 - radius * 2, y1, x2, y1 + radius * 2], 270, 360, fill=fill)
    draw.pieslice([x1, y2 - radius * 2, x1 + radius * 2, y2], 90, 180, fill=fill)
    draw.pieslice([x2 - radius * 2, y2 - radius * 2, x2, y2], 0, 90, fill=fill)

def create_app_icon(size=1024):
    """创建应用图标"""

    # 配色方案
    bg_color1 = (79, 70, 229)    # Indigo 600 #4F46E5
    bg_color2 = (124, 58, 237)   # Purple 600 #7C3AED
    white = (255, 255, 255, 255)
    cyan = (6, 182, 212, 255)    # Cyan #06B6D4

    # 创建渐变背景
    image = create_gradient_background(size, bg_color1, bg_color2)
    draw = ImageDraw.Draw(image)

    # 计算尺寸
    center_x = size // 2
    center_y = size // 2
    scale = size / 1024  # 缩放因子

    # === 绘制设计元素 ===

    # 1. 对话气泡（左边）
    bubble_size = int(280 * scale)
    bubble_x = center_x - int(150 * scale)
    bubble_y = center_y - int(80 * scale)

    # 绘制圆角矩形气泡
    draw_rounded_rectangle(
        draw,
        [bubble_x, bubble_y, bubble_x + bubble_size, bubble_y + int(200 * scale)],
        radius=int(40 * scale),
        fill=white
    )

    # 气泡尾巴（三角形）
    tail_points = [
        (bubble_x + int(60 * scale), bubble_y + int(180 * scale)),
        (bubble_x + int(30 * scale), bubble_y + int(220 * scale)),
        (bubble_x + int(90 * scale), bubble_y + int(200 * scale))
    ]
    draw.polygon(tail_points, fill=white)

    # 气泡内的省略号
    dot_y = bubble_y + int(100 * scale)
    dot_spacing = int(50 * scale)
    dot_radius = int(18 * scale)
    for i in range(3):
        dot_x = bubble_x + int(80 * scale) + i * dot_spacing
        draw.ellipse(
            [dot_x - dot_radius, dot_y - dot_radius,
             dot_x + dot_radius, dot_y + dot_radius],
            fill=bg_color1
        )

    # 2. AI 图标（右边）- 简化的机器人头像
    robot_x = center_x + int(50 * scale)
    robot_y = center_y - int(100 * scale)
    robot_size = int(240 * scale)

    # 机器人头部（圆角矩形）
    draw_rounded_rectangle(
        draw,
        [robot_x, robot_y, robot_x + robot_size, robot_y + robot_size],
        radius=int(60 * scale),
        fill=white
    )

    # 机器人天线
    antenna_width = int(20 * scale)
    antenna_height = int(60 * scale)
    antenna_x = robot_x + robot_size // 2 - antenna_width // 2
    draw.rectangle(
        [antenna_x, robot_y - antenna_height,
         antenna_x + antenna_width, robot_y],
        fill=white
    )

    # 天线顶部圆球
    ball_radius = int(25 * scale)
    draw.ellipse(
        [antenna_x + antenna_width // 2 - ball_radius,
         robot_y - antenna_height - ball_radius,
         antenna_x + antenna_width // 2 + ball_radius,
         robot_y - antenna_height + ball_radius],
        fill=cyan
    )

    # 机器人眼睛
    eye_y = robot_y + int(80 * scale)
    eye_radius = int(35 * scale)
    eye_spacing = int(100 * scale)

    # 左眼
    draw.ellipse(
        [robot_x + int(50 * scale) - eye_radius, eye_y - eye_radius,
         robot_x + int(50 * scale) + eye_radius, eye_y + eye_radius],
        fill=cyan
    )

    # 右眼
    draw.ellipse(
        [robot_x + int(50 * scale) + eye_spacing - eye_radius, eye_y - eye_radius,
         robot_x + int(50 * scale) + eye_spacing + eye_radius, eye_y + eye_radius],
        fill=cyan
    )

    # 机器人嘴巴（微笑弧线）
    mouth_y = robot_y + int(150 * scale)
    mouth_width = int(120 * scale)
    mouth_height = int(40 * scale)
    draw.arc(
        [robot_x + robot_size // 2 - mouth_width // 2, mouth_y - mouth_height // 2,
         robot_x + robot_size // 2 + mouth_width // 2, mouth_y + mouth_height // 2],
        start=0, end=180, fill=cyan, width=int(12 * scale)
    )

    # 3. 连接线（表示通信）
    line_width = int(15 * scale)
    line_start_x = bubble_x + bubble_size
    line_start_y = bubble_y + int(100 * scale)
    line_end_x = robot_x - int(10 * scale)
    line_end_y = robot_y + robot_size // 2

    # 绘制虚线连接
    segments = 5
    for i in range(segments):
        if i % 2 == 0:
            seg_start_x = line_start_x + (line_end_x - line_start_x) * i // segments
            seg_start_y = line_start_y + (line_end_y - line_start_y) * i // segments
            seg_end_x = line_start_x + (line_end_x - line_start_x) * (i + 1) // segments
            seg_end_y = line_start_y + (line_end_y - line_start_y) * (i + 1) // segments
            draw.line([seg_start_x, seg_start_y, seg_end_x, seg_end_y],
                     fill=white, width=line_width)

    return image

# 生成不同尺寸的图标
if __name__ == "__main__":
    print("🎨 生成 AI Agent Hub 应用图标...")

    # 生成 1024x1024 主图标
    icon_1024 = create_app_icon(1024)
    icon_1024.save("app_icon_1024.png")
    print("✅ 生成 1024x1024 图标")

    # 生成其他常用尺寸
    sizes = [512, 256, 192, 128, 96, 72, 48]
    for size in sizes:
        icon = icon_1024.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(f"app_icon_{size}.png")
        print(f"✅ 生成 {size}x{size} 图标")

    print("\n🎉 所有图标生成完成！")
    print("\n生成的文件：")
    print("  - app_icon_1024.png (主图标)")
    print("  - app_icon_512.png")
    print("  - app_icon_256.png")
    print("  - app_icon_192.png (Android)")
    print("  - app_icon_128.png")
    print("  - app_icon_96.png")
    print("  - app_icon_72.png")
    print("  - app_icon_48.png")
