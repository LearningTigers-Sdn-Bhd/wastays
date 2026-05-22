require "base64"

module Concierge
  class QrSvg
    def self.for(payload, color: "0a2e29", module_size: 6)
      qr = RQRCode::QRCode.new(payload)
      svg = qr.as_svg(
        color: color,
        shape_rendering: "crispEdges",
        module_size: module_size,
        offset: 0,
        viewbox: true,
        standalone: true,
        use_path: true
      )
      svg.gsub(/\s+(width|height)="[^"]*"/, "")
         .sub(/<svg/, '<svg style="width:100%;height:100%;display:block;"')
    end

    def self.data_url(payload, color: "0a2e29", module_size: 6)
      svg = self.for(payload, color: color, module_size: module_size)
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end

    def self.png(payload, size: 600)
      RQRCode::QRCode.new(payload).as_png(size: size).to_s
    end
  end
end
