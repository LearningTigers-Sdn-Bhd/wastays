# frozen_string_literal: true

module GuestUI
  # A short status a guest has to read before the content under it: a code that
  # did not match, a link that was mailed, a request the hotel already has.
  #
  # The variant is never the message. A guest who cannot separate the tints
  # still gets the whole fact from the words, so a danger notice says what went
  # wrong rather than turning red and leaving them to work it out.
  #
  # An error notice takes `role="alert"`, so a guest whose form came back
  # invalid hears why without hunting for it.
  class Notice < GuestUI::BaseComponent
    VARIANTS = %i[info success warning danger].freeze
    ICONS = {
      info: "info",
      success: "circle-check",
      warning: "triangle-alert",
      danger: "circle-alert"
    }.freeze

    def initialize(message: nil, title: nil, variant: :info, icon: true, alert: nil,
                   class: nil, **attributes)
      @message = message
      @title = title
      @variant = VARIANTS.include?(variant) ? variant : :info
      @icon = icon
      @alert = alert
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    # Nothing to say, nothing drawn. Callers pass a message straight from the
    # controller, which is blank on the first visit to every form.
    def render?
      content.present? || @message.present? || @title.present?
    end

    def call
      tag.div(**notice_attributes) do
        safe_join([ icon_tag, body ].compact)
      end
    end

    private

    def alert? = @alert.nil? ? @variant == :danger : @alert

    def icon_tag
      return unless @icon

      helpers.app_icon(ICONS.fetch(@variant), class: "guest-notice__icon", aria: { hidden: "true" })
    end

    def body
      tag.div do
        safe_join([
          (tag.span(@title, class: "guest-notice__title") if @title.present?),
          tag.span(content.presence || @message, class: "guest-notice__message")
        ].compact)
      end
    end

    def notice_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        role: (alert? ? "alert" : nil),
        class: tw_merge("guest-notice", @class),
        data: data.merge(variant: @variant)
      ).compact
    end
  end
end
