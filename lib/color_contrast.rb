# WCAG 2.2 contrast checking for oklch()/hex design tokens.
# oklch values are already linear once converted to LMS/XYZ — do NOT re-apply
# sRGB gamma linearization to them (only hex/rgb inputs need that step).
module ColorContrast
  module_function

  def contrast(value_a, value_b)
    l1 = luminance(value_a)
    l2 = luminance(value_b)
    hi, lo = [ l1, l2 ].max, [ l1, l2 ].min
    (hi + 0.05) / (lo + 0.05)
  end

  # Composite a translucent `fg` (oklch(... / A) or rgb(... / A)) over an
  # opaque `bg` in linear sRGB space, returning an opaque linear [r,g,b].
  def composite(fg, bg)
    r1, g1, b1, a = linear_rgba(fg)
    return [ r1, g1, b1 ] if a.nil? || a >= 1.0

    r2, g2, b2, = linear_rgba(bg)
    [
      a * r1 + (1 - a) * r2,
      a * g1 + (1 - a) * g2,
      a * b1 + (1 - a) * b2
    ]
  end

  def luminance(value)
    r, g, b, a = linear_rgba(value)
    if a && a < 1.0
      raise ArgumentError, "translucent value #{value.inspect} must be composited first via ColorContrast.composite"
    end
    rec709(r, g, b)
  end

  def rec709(r, g, b)
    0.2126 * clamp(r) + 0.7152 * clamp(g) + 0.0722 * clamp(b)
  end

  def clamp(c)
    c.negative? ? 0.0 : (c > 1.0 ? 1.0 : c)
  end

  # Returns [r, g, b, alpha] in LINEAR sRGB. alpha is nil when opaque/unspecified.
  def linear_rgba(value)
    value = value.strip
    case value
    when /\Aoklch\(/i
      oklch_to_linear_srgb(value)
    when /\A#/
      hex_to_linear_srgb(value)
    when /\Argba?\(/i
      rgb_to_linear_srgb(value)
    else
      raise ArgumentError, "unrecognized color value: #{value.inspect}"
    end
  end

  # oklch(L C H) or oklch(L C H / A) -- L 0..1, C chroma, H degrees, A 0..1 or %
  def oklch_to_linear_srgb(value)
    m = value.match(/oklch\(\s*([\d.]+%?)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+%?))?\s*\)/i)
    raise ArgumentError, "bad oklch(): #{value.inspect}" unless m

    l = parse_percent_or_number(m[1], base: 1.0)
    c = m[2].to_f
    h = m[3].to_f
    a = m[4] ? parse_percent_or_number(m[4], base: 1.0) : nil

    a_ok = c * Math.cos(h * Math::PI / 180.0)
    b_ok = c * Math.sin(h * Math::PI / 180.0)

    l_ = l + 0.3963377774 * a_ok + 0.2158037573 * b_ok
    m_ = l - 0.1055613458 * a_ok - 0.0638541728 * b_ok
    s_ = l - 0.0894841775 * a_ok - 1.2914855480 * b_ok

    l3, m3, s3 = l_**3, m_**3, s_**3

    r =  4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
    g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
    b =  -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

    [ r, g, b, a ]
  end

  def hex_to_linear_srgb(value)
    hex = value.delete("#")
    hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
    r, g, b = [ 0, 2, 4 ].map { |i| hex[i, 2].to_i(16) / 255.0 }
    a = hex.length >= 8 ? hex[6, 2].to_i(16) / 255.0 : nil
    [ srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a ]
  end

  def rgb_to_linear_srgb(value)
    m = value.match(/rgba?\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+%?))?\s*\)/i) ||
        value.match(/rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+%?))?\s*\)/i)
    raise ArgumentError, "bad rgb(): #{value.inspect}" unless m

    r, g, b = m[1].to_f / 255.0, m[2].to_f / 255.0, m[3].to_f / 255.0
    a = m[4] ? parse_percent_or_number(m[4], base: 1.0) : nil
    [ srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a ]
  end

  # Normative WCAG threshold (0.03928), matches axe-core; not the ICC-corrected 0.04045.
  def srgb_to_linear(c)
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
  end

  def parse_percent_or_number(str, base:)
    str.end_with?("%") ? (str.to_f / 100.0) * base : str.to_f
  end
end
