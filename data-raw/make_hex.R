library(hexSticker)
library(ggplot2)
library(showtext)
library(sysfonts)

font_add_google("Lato", "lato")
showtext_auto()

navy   <- "#0d2137"
border <- "#2166ac"
accent <- "#8ecae6"
white  <- "#ffffff"

left_names <- c("Joe Biden", "B. Obama", "D. Trump", "B. Clinton")
right_names <- c("Joseph R. Biden",
                 "Barack H. Obama",
                 "Donald J. Trump",
                 "Wm. J. Clinton")

df_left  <- data.frame(x = 0, y = seq(3.5, 0.5, length.out = 4),
                       label = left_names)
df_right <- data.frame(x = 4, y = seq(3.5, 0.5, length.out = 4),
                       label = right_names)

curves <- data.frame(
  x    = 0.9,
  xend = 3.1,
  y    = df_left$y,
  yend = df_right$y
)

p <- ggplot() +
  geom_curve(data = curves,
             aes(x = x, y = y, xend = xend, yend = yend),
             curvature = -0.25, linewidth = 0.7,
             color = accent, alpha = 0.85,
             lineend = "round") +
  geom_curve(data = curves,
             aes(x = x, y = y, xend = xend, yend = yend),
             curvature = 0.25, linewidth = 0.35,
             color = accent, alpha = 0.35,
             linetype = "dotted") +
  geom_label(data = df_left,
             aes(x = x, y = y, label = label),
             family = "lato", size = 3.2, color = white,
             fill = navy, label.size = 0.35,
             label.r = grid::unit(0.12, "lines"),
             label.padding = grid::unit(0.18, "lines")) +
  geom_label(data = df_right,
             aes(x = x, y = y, label = label),
             family = "lato", size = 3.2, color = white,
             fill = navy, label.size = 0.35,
             label.r = grid::unit(0.12, "lines"),
             label.padding = grid::unit(0.18, "lines")) +
  xlim(-1.2, 5.2) + ylim(-0.2, 4.2) +
  theme_void() +
  theme(
    panel.background = element_rect(fill = "transparent", color = NA),
    plot.background  = element_rect(fill = "transparent", color = NA)
  )

out <- "C:/Users/jo22058/Documents/projects/r-packages/fuzzylink/man/figures/logo.png"
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)

sticker(
  p,
  package  = "fuzzylink",
  p_size   = 22,
  p_y      = 1.48,
  p_color  = white,
  p_family = "lato",
  s_x      = 1,
  s_y      = 0.82,
  s_width  = 1.55,
  s_height = 1.05,
  h_fill   = navy,
  h_color  = border,
  h_size   = 1.6,
  white_above_package = FALSE,
  filename = out,
  dpi      = 300
)
