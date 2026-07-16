# frozen_string_literal: true

module PanelsUI
  # Blocking confirmation dialog with explicit cancel and action responses.
  #
  # AlertDialog renders only the dialog surface. Open it with a native invoker:
  #
  #   <button command="show-modal" commandfor="delete-room">Delete room</button>
  #
  # It deliberately reuses the native-dialog controller in non-dismissible mode,
  # so Escape and backdrop clicks cannot bypass the required response.
  class AlertDialog < PanelsUI::BaseComponent
    SIZES = %i[default sm].freeze
    TONES = %i[default info warning success destructive].freeze
    ACTION_VARIANTS = {
      default: :primary,
      info: :info,
      warning: :warning,
      success: :success,
      destructive: :destructive
    }.freeze

    class Response < PanelsUI::BaseComponent
      def initialize(label:, slot:, variant:, href: nil, method: nil, form: {}, autofocus: false,
                     class: nil, **attributes)
        @label = label
        @slot = slot
        @variant = variant
        @href = href
        @method = method&.to_sym
        @form = form
        @autofocus = autofocus
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        return method_button if method_button?

        render PanelsUI::Button.new(
          label: @label,
          variant: @variant,
          size: :md,
          as: (@href.present? ? :a : :button),
          href: @href,
          autofocus: @autofocus,
          class: @class,
          **response_attributes
        )
      end

      private

      def method_button?
        @href.present? && @method.present? && @method != :get
      end

      def method_button
        helpers.button_to(
          @href,
          method: @method,
          form: { class: "contents" }.merge(@form),
          **response_attributes.merge(
            type: "submit",
            autofocus: @autofocus,
            class: tw_merge("panel-button", @class),
            data: response_data.merge(variant: @variant, size: :md)
          )
        ) { @label }
      end

      def response_attributes
        attributes = @attributes.deep_dup
        attributes.delete(:data)
        attributes.delete("data")
        attributes.merge(data: response_data)
      end

      def response_data
        data = (@attributes[:data] || @attributes["data"] || {}).deep_dup
        caller_action = data.delete(:action) || data.delete("action")
        data.merge(
          slot: @slot,
          action: [ caller_action, "panels-ui--dialog#close" ].compact.join(" ")
        )
      end
    end

    renders_one :icon
    renders_one :cancel, lambda { |label:, variant: nil, **attributes|
      Response.new(
        label: label,
        slot: "alert-dialog-cancel",
        variant: normalized_button_variant(variant, default_cancel_variant),
        autofocus: true,
        **attributes
      )
    }
    renders_one :action, lambda { |label:, variant: nil, href: nil, method: nil, form: {}, **attributes|
      Response.new(
        label: label,
        slot: "alert-dialog-action",
        variant: normalized_button_variant(variant, ACTION_VARIANTS.fetch(@tone)),
        href: href,
        method: method,
        form: form,
        **attributes
      )
    }

    def initialize(id:, title:, description:, size: :default, tone: :default, class: nil, **attributes)
      @id = id
      @title = title
      @description = description
      @size = SIZES.include?(size) ? size : :default
      @tone = TONES.include?(tone) ? tone : :default
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      raise ArgumentError, "AlertDialog requires a title" if @title.blank?
      raise ArgumentError, "AlertDialog requires a description" if @description.blank?
      raise ArgumentError, "AlertDialog requires a cancel response" unless cancel?
      raise ArgumentError, "AlertDialog requires an action response" unless action?
    end

    def title_id = "#{@id}-title"
    def desc_id = "#{@id}-description"

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}
      aria = attributes.delete(:aria) || attributes.delete("aria") || {}
      caller_controller = data.delete(:controller) || data.delete("controller")
      caller_action = data.delete(:action) || data.delete("action")

      attributes.merge(
        id: @id,
        role: "alertdialog",
        class: tw_merge("panel-alert-dialog", @class),
        data: data.merge(
          slot: "alert-dialog-content",
          size: @size,
          tone: @tone,
          controller: [ "panels-ui--dialog", caller_controller ].compact.join(" "),
          panels_ui__dialog_dismissible_value: false,
          action: [
            "close->panels-ui--dialog#onClose",
            "cancel->panels-ui--dialog#onCancel",
            "click->panels-ui--dialog#backdropClose",
            caller_action
          ].compact.join(" ")
        ),
        aria: aria.merge(
          modal: "true",
          labelledby: title_id,
          describedby: desc_id
        )
      ).compact
    end

    private

    def default_cancel_variant
      @tone == :default ? :neutral : :ghost
    end

    def normalized_button_variant(value, fallback)
      PanelsUI::Button::VARIANTS.include?(value) ? value : fallback
    end
  end
end
