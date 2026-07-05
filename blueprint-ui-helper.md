# Home Blueprint UI Helper

This guide is for tweaking the blueprint section on the Home tab without needing to become a Swift developer. Think of the blueprint as a fixed-height React component with absolutely positioned children.

## Run The App In Simulator

Run these from the repo root:

```sh
LAUNCH_APP=true scripts/build-install-simulator.sh
```

That script does the iOS version of "build, open the preview target, and show my changes":

- finds the simulator named `iPhone 17 Pro`
- boots it if needed
- opens the Simulator app
- clean-builds the `LevyHome` scheme
- installs the latest build
- launches Levy Home when `LAUNCH_APP=true`

If your installed simulator has a different name:

```sh
xcrun simctl list devices available
SIMULATOR_NAME="Exact iPhone Name From The List" LAUNCH_APP=true scripts/build-install-simulator.sh
```

If Levy Home is already installed and you only need to reopen it:

```sh
xcrun simctl launch booted com.levyhome.app
```

If the UI looks stale after a rebuild, terminate and relaunch:

```sh
xcrun simctl terminate booted com.levyhome.app
xcrun simctl launch booted com.levyhome.app
```

Xcode alternative:

```sh
open LevyHome.xcodeproj
```

Then select the `LevyHome` scheme, pick an iPhone simulator, and press `Cmd-R`. This is usually the most Vite-like loop because Xcode does incremental rebuilds. The terminal script intentionally does a clean build, so it is more reliable but slower.

## Where The Blueprint Lives

Main file:

```text
LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift
```

The Home screen renders it from:

```text
LevyHome/Views/Home/HomeContentView.swift
```

Current call site: `HomeContentView.swift` lines 56-66. You usually do not need to edit that call site for visual blueprint layout changes.

The blueprint's visual pieces are all in `HomeBlueprintView.swift`:

| What you want to change | Where to look |
| --- | --- |
| Blueprint card height | line 125 |
| Center home node position | line 16 |
| Normal node size | line 17 |
| Garage node size | line 18 |
| Center home node size | line 19 |
| Foreground room/garage positions | lines 163-179 |
| Connector line thickness | line 51 |
| Node icon/text styling | lines 181-255 |
| Background floor-plan lines | lines 286-338 |
| Background decorative sparks | lines 360-379 |
| Blueprint colors | `LevyHome/Models/Home/HomePalette.swift` |

## SwiftUI Positioning In React Terms

The blueprint uses a `GeometryReader`, which is roughly like measuring a component with a `ResizeObserver`.

At the top of `HomeBlueprintView.swift`, lines 12-20 calculate the blueprint's local layout values:

```swift
let width = geometry.size.width
let height = geometry.size.height
let center = CGPoint(x: width * 0.50, y: height * 0.54)
let nodeSize = min(max(width * 0.225, 78), 92)
let garageSize = min(max(width * 0.305, 112), 134)
let centerSize = min(max(width * 0.185, 66), 80)
let positions = BlueprintNodePositions(width: width, height: height)
```

React-ish translation:

```tsx
const width = container.width
const height = container.height
const center = { x: width * 0.50, y: height * 0.54 }
```

SwiftUI coordinates work like the browser:

- `x` increases as you move right
- `y` increases as you move down
- `CGPoint(x:y:)` is a point
- `.position(point)` places the center of the view at that point
- values like `width * 0.82` are percentages of the blueprint's rendered width
- values like `height * 0.56` are percentages of the blueprint's rendered height

The blueprint card is currently `350` points tall on line 125:

```swift
.frame(height: 350)
```

So changing a y multiplier by `0.05` moves something by about `17.5` points because `350 * 0.05 = 17.5`.

## Foreground Node Map

Foreground nodes are the visible circles: Home, Kitchen, Upstairs, Study, Playroom, Entry, and Garage.

The individual room/garage positions are here, in `BlueprintNodePositions`:

```swift
private struct BlueprintNodePositions {
    let kitchen: CGPoint
    let upstairsHall: CGPoint
    let study: CGPoint
    let garage: CGPoint
    let entry: CGPoint
    let playroom: CGPoint

    init(width: CGFloat, height: CGFloat) {
        kitchen = CGPoint(x: width * 0.48, y: height * 0.31)
        upstairsHall = CGPoint(x: width * 0.72, y: height * 0.32)
        study = CGPoint(x: width * 0.82, y: height * 0.56)
        garage = CGPoint(x: width * 0.77, y: height * 0.84)
        entry = CGPoint(x: width * 0.29, y: height * 0.76)
        playroom = CGPoint(x: width * 0.19, y: height * 0.52)
    }
}
```

Current source lines: 163-179.

Important: the connector lines use these same points. The visible Study node is positioned with `positions.study` on line 85, and the Study connector endpoint is also `positions.study` in the connector list on line 43. That means moving `study` in `BlueprintNodePositions` moves the icon, text, circle, and connector endpoint together.

## Move All Foreground Nodes Together

There are two reasonable ways to do this.

### Option A: Add A Shared Offset

This is the easiest to keep tinkering with because it gives you one knob.

In `HomeBlueprintView.swift`, replace the current `center` line 16 and `positions` line 20 with this pattern. Leave the `nodeSize`, `garageSize`, and `centerSize` lines between them:

```swift
let foregroundOffset = CGPoint(x: 0, y: -18)
let center = CGPoint(
    x: width * 0.50 + foregroundOffset.x,
    y: height * 0.54 + foregroundOffset.y
)
let positions = BlueprintNodePositions(width: width, height: height, offset: foregroundOffset)
```

Then update the `BlueprintNodePositions` initializer around lines 171-178:

```swift
init(width: CGFloat, height: CGFloat, offset: CGPoint = .zero) {
    kitchen = CGPoint(x: width * 0.48 + offset.x, y: height * 0.31 + offset.y)
    upstairsHall = CGPoint(x: width * 0.72 + offset.x, y: height * 0.32 + offset.y)
    study = CGPoint(x: width * 0.82 + offset.x, y: height * 0.56 + offset.y)
    garage = CGPoint(x: width * 0.77 + offset.x, y: height * 0.84 + offset.y)
    entry = CGPoint(x: width * 0.29 + offset.x, y: height * 0.76 + offset.y)
    playroom = CGPoint(x: width * 0.19 + offset.x, y: height * 0.52 + offset.y)
}
```

What happens:

- `foregroundOffset.y = -18` moves all foreground nodes and connector lines up 18 points
- `foregroundOffset.y = 18` moves them down 18 points
- `foregroundOffset.x = -12` moves them left 12 points
- `foregroundOffset.x = 12` moves them right 12 points

This is like wrapping all absolutely positioned React children in a translated group.

### Option B: Change Every Multiplier By The Same Amount

You can also edit the existing values directly.

Example: to move all room/garage nodes up by about 17.5 points, subtract `0.05` from every y multiplier on lines 172-177:

```swift
kitchen = CGPoint(x: width * 0.48, y: height * 0.26)       // was 0.31
upstairsHall = CGPoint(x: width * 0.72, y: height * 0.27)  // was 0.32
study = CGPoint(x: width * 0.82, y: height * 0.51)         // was 0.56
garage = CGPoint(x: width * 0.77, y: height * 0.79)        // was 0.84
entry = CGPoint(x: width * 0.29, y: height * 0.71)         // was 0.76
playroom = CGPoint(x: width * 0.19, y: height * 0.47)      // was 0.52
```

If you also want the center Home node to move with them, change line 16 too:

```swift
let center = CGPoint(x: width * 0.50, y: height * 0.49) // was 0.54
```

The shared-offset option is cleaner if you plan to experiment a lot.

## Move One Foreground Node

Edit that node's `CGPoint` in `BlueprintNodePositions`.

Example 1: move Study left.

Current line 174:

```swift
study = CGPoint(x: width * 0.82, y: height * 0.56)
```

Change it to:

```swift
study = CGPoint(x: width * 0.72, y: height * 0.56)
```

What happens: Study moves left by 10% of the blueprint width. On a 360-point-wide phone layout, that is about 36 points. The Study icon, text, circle, and connecting line endpoint all move left together.

Example 2: move Garage up.

Current line 175:

```swift
garage = CGPoint(x: width * 0.77, y: height * 0.84)
```

Change it to:

```swift
garage = CGPoint(x: width * 0.77, y: height * 0.74)
```

What happens: Garage moves up by 10% of the blueprint height. Since the blueprint is currently 350 points tall, that is about 35 points. The Garage button, icon, status text, warning badge, spinner, and connector line endpoint all move up together.

Example 3: move Playroom down and right.

Current line 177:

```swift
playroom = CGPoint(x: width * 0.19, y: height * 0.52)
```

Change it to:

```swift
playroom = CGPoint(x: width * 0.25, y: height * 0.58)
```

What happens: Playroom moves right by 6% of the width and down by 6% of the height.

Rule of thumb:

- change `x` down to move left
- change `x` up to move right
- change `y` down to move up
- change `y` up to move down
- keep most values between about `0.10` and `0.90` so the circles do not clip against the card edges

## Move The Center Home Node

The center home position is line 16:

```swift
let center = CGPoint(x: width * 0.50, y: height * 0.54)
```

Example: move Home slightly up:

```swift
let center = CGPoint(x: width * 0.50, y: height * 0.48)
```

What happens: the center Home circle moves up, and all connector lines start from the new center point. The outer room nodes stay where they are.

If you want to move the visual Home circle without moving the connector start points, you would need separate variables, for example `connectorCenter` and `homeNodeCenter`. I would avoid that unless you intentionally want the lines to look detached.

## Adjust Connector Line Width

The foreground connector lines are drawn on lines 38-52:

```swift
ConnectorLines(
    center: center,
    points: [
        positions.kitchen,
        positions.upstairsHall,
        positions.study,
        positions.garage,
        positions.entry,
        positions.playroom
    ]
)
.stroke(
    HomePalette.connector,
    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
)
```

The width knob is line 51:

```swift
StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
```

Examples:

```swift
StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
```

Makes the connectors thinner and more subtle.

```swift
StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
```

Makes the connectors thicker and more pill-like.

The background floor-plan lines also use `.stroke(...)`, but that is separate. The foreground connector line width is the `lineWidth: 9` on line 51. The background floor-plan line width is the `lineWidth: 1` on line 35.

## Adjust Node Sizes

Near lines 17-19:

```swift
let nodeSize = min(max(width * 0.225, 78), 92)
let garageSize = min(max(width * 0.305, 112), 134)
let centerSize = min(max(width * 0.185, 66), 80)
```

React-ish translation:

```ts
const nodeSize = clamp(width * 0.225, 78, 92)
```

The pattern is:

```swift
min(max(preferredSize, minimumSize), maximumSize)
```

Examples:

```swift
let nodeSize = min(max(width * 0.245, 84), 100)
```

Normal nodes get larger. They will prefer 24.5% of the blueprint width, never shrink below 84 points, and never grow above 100 points.

```swift
let garageSize = min(max(width * 0.285, 104), 124)
```

Garage gets smaller. This can help if it feels crowded near the bottom edge.

## Adjust Icon And Text Inside Nodes

Node internals live in `BlueprintNodeView`, lines 181-255.

Useful knobs:

| What | Current line | What to change |
| --- | --- | --- |
| Outer white circle border | line 197 | `lineWidth: 2` |
| Colored arc thickness | line 205 | `isPriority ? 4 : 3` |
| Arc padding | line 208 | `isPriority ? 8 : 6` |
| Vertical spacing between icon and text | line 210 | `VStack(spacing: ...)` |
| Icon size | line 217 | `isPriority ? 32 : 22` |
| Title size | line 224 | `isPriority ? 20 : 16` |
| Subtitle size | line 231 | `isPriority ? 14 : 12` |
| Warning badge offset | line 250 | `.offset(x: size * 0.32, y: -size * 0.32)` |

Example: make normal node icons larger, but leave Garage as-is:

Current line 217:

```swift
.font(.system(size: isPriority ? 32 : 22, weight: .medium))
```

Change it to:

```swift
.font(.system(size: isPriority ? 32 : 26, weight: .medium))
```

What happens: Kitchen, Upstairs, Study, Playroom, and Entry icons get larger. Garage is `isPriority`, so it stays at 32.

Example: move the Garage warning badge farther out:

Current line 250:

```swift
.offset(x: size * 0.32, y: -size * 0.32)
```

Change it to:

```swift
.offset(x: size * 0.38, y: -size * 0.38)
```

What happens: the warning triangle moves farther toward the top-right edge of the Garage circle.

## Change Labels, Icons, Or Tones

Each foreground node is created in the `ZStack`, lines 57-122.

Example Study node, lines 78-85:

```swift
BlueprintNodeView(
    title: "Study",
    subtitle: "idle",
    systemImage: "lamp.desk",
    tone: .success,
    size: nodeSize
)
.position(positions.study)
```

Useful changes:

```swift
title: "Office"
```

Changes the label from Study to Office.

```swift
subtitle: "reading"
```

Changes the small status text.

```swift
systemImage: "desktopcomputer"
```

Changes the SF Symbol icon. The icon names are Apple's SF Symbols strings. If you install/open the SF Symbols app from Apple, you can search for names visually.

```swift
tone: .accent
```

Changes the colored arc and subtitle color. Available tones are defined in `LevyHome/Views/Shared/StatusBadgeView.swift`: `.neutral`, `.accent`, `.success`, `.warning`, and `.critical`.

Garage is different because it is a real button. The Garage node is lines 105-122. It uses live status data:

```swift
systemImage: garageData.systemImage
tone: garageData.tone
subtitle: garageSubtitle
```

You can move or resize Garage safely, but be more careful changing its data wiring because tapping it controls the real garage quick action path.

## Add A New Foreground Node

Suppose you want to add a Pantry node.

1. Add a property in `BlueprintNodePositions` near lines 163-169:

```swift
let pantry: CGPoint
```

2. Add its position in the initializer near lines 172-177:

```swift
pantry = CGPoint(x: width * 0.40, y: height * 0.64)
```

3. Add it to the connector points list near lines 40-47 if you want a line from Home to Pantry:

```swift
positions.pantry
```

4. Add the visible node in the `ZStack`, near the other `BlueprintNodeView` blocks:

```swift
BlueprintNodeView(
    title: "Pantry",
    subtitle: "stocked",
    systemImage: "shippingbox",
    tone: .accent,
    size: nodeSize
)
.position(positions.pantry)
```

If you do not want a connector line, skip step 3.

## Background Nodes And Blueprint Details

There are not named "background node" models like there are foreground nodes. The background is made of three pieces:

1. The rounded blueprint card
2. The pale floor-plan lines and small room boxes
3. The decorative asterisk marks

### Rounded Blueprint Card

The card itself is lines 23-32:

```swift
RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    .fill(HomePalette.blueprintFill)
```

The gradient color lives in `LevyHome/Models/Home/HomePalette.swift`, lines 20-33.

Example: make the card corners less rounded.

Current line 15:

```swift
let cornerRadius: CGFloat = 26
```

Change it to:

```swift
let cornerRadius: CGFloat = 18
```

What happens: the outer blueprint card and clipped floor-plan background get squarer corners.

### Floor-Plan Lines

The floor-plan background is drawn on lines 34-36:

```swift
FloorPlanLines()
    .stroke(HomePalette.floorLine, lineWidth: 1)
```

The actual line coordinates are in `FloorPlanLines`, lines 286-338.

The helper inside that shape is:

```swift
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
}
```

That means this background line:

```swift
[point(0.05, 0.22), point(0.28, 0.22), point(0.28, 0.08)]
```

is like an SVG polyline with percentage-based points:

```tsx
<polyline points="5% 22%, 28% 22%, 28% 8%" />
```

Example: move the upper-left background wall lower.

Current line 295:

```swift
[point(0.05, 0.22), point(0.28, 0.22), point(0.28, 0.08)]
```

Change it to:

```swift
[point(0.05, 0.28), point(0.28, 0.28), point(0.28, 0.08)]
```

What happens: the horizontal segment moves down because its y value changed from `0.22` to `0.28`. The final vertical segment still ends at `0.08`.

Example: make background floor-plan lines thicker.

Current line 35:

```swift
.stroke(HomePalette.floorLine, lineWidth: 1)
```

Change it to:

```swift
.stroke(HomePalette.floorLine, lineWidth: 2)
```

What happens: only the background floor-plan lines get thicker. The foreground connector lines do not change.

### Small Background Room Boxes

The small rounded boxes are the `rooms` array on lines 316-322:

```swift
CGRect(x: rect.width * 0.13, y: rect.height * 0.58, width: rect.width * 0.08, height: rect.height * 0.10)
```

React/CSS translation:

```css
left: 13%;
top: 58%;
width: 8%;
height: 10%;
```

Example: make that room wider.

```swift
CGRect(x: rect.width * 0.13, y: rect.height * 0.58, width: rect.width * 0.14, height: rect.height * 0.10)
```

What happens: that small rounded background room box gets wider.

### Decorative Asterisk Marks

The decorative background marks are in `BlueprintDecorations`, lines 360-379:

```swift
decorativeSpark(at: CGPoint(x: width * 0.12, y: height * 0.16))
decorativeSpark(at: CGPoint(x: width * 0.92, y: height * 0.14))
decorativeSpark(at: CGPoint(x: width * 0.92, y: height * 0.63))
decorativeSpark(at: CGPoint(x: width * 0.49, y: height * 0.75))
```

Example: move the top-right spark left.

Current line 367:

```swift
decorativeSpark(at: CGPoint(x: width * 0.92, y: height * 0.14))
```

Change it to:

```swift
decorativeSpark(at: CGPoint(x: width * 0.82, y: height * 0.14))
```

What happens: that background mark moves left by 10% of the blueprint width.

To remove one, delete its `decorativeSpark(...)` line. To add one, copy a line and change the x/y multipliers.

## Common Gotchas

- `.position(...)` places the center of the node, not its top-left corner.
- `y` works like CSS `top`: larger values move down.
- The foreground connector endpoints come from the same `positions.*` values as the visible nodes.
- If a node is clipped, pull its x/y multiplier away from the edges or reduce `nodeSize` / `garageSize`.
- The Garage node is a `Button`, so keep the `Button { onGarageTapped() } label: { ... }` wrapper unless you intentionally want to remove tap behavior.
- The center Home node is not currently a button.
- `systemImage` values are SF Symbols names. Invalid names can make icons disappear.
- Rebuild after Swift changes. There is no Vite-style hot module reload for this app.
- If changing colors, check `HomePalette.swift` first because the blueprint intentionally reuses shared palette values.

## My Recommended Tinkering Order

1. Start with node positions in `BlueprintNodePositions`.
2. Tune connector width on line 51.
3. Tune node sizes on lines 17-19.
4. Adjust icon/text sizing inside `BlueprintNodeView`.
5. Only then tweak background `FloorPlanLines` or palette colors.

That order keeps the main visual layout under control before you start changing the decorative layer.
