#import "@preview/polylux:0.4.0": *
#import "@preview/rustycure:0.2.0": qr-code

#let title = "Cross-Building & Cross-Testing"
#let release = "2026-05-19"
#let url = "github.com/s-m-e/cross-building-and-testing-with-rust"
#let color_bg = rgb("#333132")
#let color_fg = rgb("#bfbfbf")

#set page(
  paper: "presentation-16-9",
  footer: align(
    bottom,
    toolbox.full-width-block(
      fill: color_bg,
      inset: 8mm,
    )[
      #text(size: 12pt)[#release | #title | #url]
      #h(1fr)
      #text(size: 16pt)[#toolbox.slide-number / #toolbox.last-slide-number]
    ]
  ),
  margin: (bottom: 2em, rest: 1em),
  fill: rgb(color_bg),
)
#set text(
  font: "Open Sans",
  size: 22pt,
  fill: color_fg,
)
#show heading: set block(below: 2em)

#slide[
  #set page(footer: none)
  #set align(horizon)

  #qr-code(
    "https://" + url,
    width: 80mm,
    quiet-zone: false,
    dark-color: color_fg,
    light-color: color_bg,
  )

  #text(1.5em)[#title] \
  #text(0.8em)[Rust User Group Leipzig, #release]

  Sebastian M. Ernst \<ernst\@pleiszenburg.de\>
]

#slide[
  = Why?
  #show: later

  - #strike[masoch*sm]
  - vibe coding!

]

#slide[
  = Further reading

  #show: later
  - https://www.qemu.org/documentation/
  - https://github.com/cross-rs/cross
  - https://github.com/dockcross/dockcross
]
