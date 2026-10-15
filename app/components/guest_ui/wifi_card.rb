# frozen_string_literal: true

module GuestUI
  # One Wi-Fi network a guest joins: its name, its password, the steps staff
  # wrote, and a code another device can scan to join.
  #
  # The name and the password each have a Copy button. A guest types them
  # into another screen, often a laptop, and a mistyped password is the most
  # common Wi-Fi call to the front desk. A screen reader hears the result of
  # a copy from the status line.
  #
  # The join code sits behind a disclosure. The phone showing this page cannot
  # scan its own screen, so the code is for a second device: a tablet, a
  # partner's phone.
  class WifiCard < GuestUI::BaseComponent
    def initialize(label:, ssid:, password: nil, primary: false, instructions: nil, class: nil, **attributes)
      @label = label
      @ssid = ssid
      @password = password.presence
      @primary = primary
      @steps = instructions.to_s.lines.map { |line| line.strip.sub(/\A(\d+[.)]|[•\-*])\s+/, "") }.compact_blank
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :label, :ssid, :password, :steps

    def subtitle = ("Main network" if @primary)

    # The join format phones read from a camera. A backslash escapes the
    # characters the format uses itself.
    def join_payload
      type = password ? "WPA" : "nopass"
      [ "WIFI:T:#{type}", "S:#{escape(ssid)}", ("P:#{escape(password)}" if password) ].compact.join(";") + ";;"
    end

    def qr_data_url = ::Concierge::QrSvg.data_url(join_payload)

    def escape(value) = value.to_s.gsub(/([\;,:"])/) { "\\#{::Regexp.last_match(1)}" }

    def card_attributes
      @attributes.merge(class: tw_merge("guest-wifi", @class), data: { controller: "clipboard", clipboard_success_text_value: "Copied" })
    end
  end
end
