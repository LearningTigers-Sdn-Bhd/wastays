# frozen_string_literal: true

module PanelsUI
  class Attachment < PanelsUI::BaseComponent
    class Media < PanelsUI::BaseComponent
      VARIANTS = %i[icon image].freeze

      attr_reader :variant

      def initialize(variant: :icon, class: nil, **attributes)
        @variant = VARIANTS.include?(variant) ? variant : :icon
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.div(content, **attributes.merge(
          class: tw_merge("panel-attachment__media", @class),
          data: data.merge(variant: @variant)
        ))
      end
    end

    class Actions < PanelsUI::BaseComponent
      def initialize(class: nil, **attributes)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        tag.div(content, **@attributes.merge(class: tw_merge("panel-attachment__actions", @class)))
      end
    end

    class Trigger < PanelsUI::BaseComponent
      def initialize(href: nil, aria_label: nil, class: nil, **attributes)
        @href = href
        @aria_label = aria_label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}
        aria[:label] ||= @aria_label

        if aria[:label].blank? && aria["label"].blank?
          raise ArgumentError, "Attachment triggers require an aria_label or aria: { label: ... }"
        end

        tag.public_send(tag_name, "", **attributes.merge(
          href: @href,
          type: (@href.present? ? nil : attributes.delete(:type) || "button"),
          class: tw_merge("panel-attachment__trigger", @class),
          data: data.merge(slot: "attachment-trigger"),
          aria: aria
        ).compact)
      end

      private

      def tag_name = @href.present? ? :a : :button
    end

    renders_one :media, ->(**attributes) { Media.new(**attributes) }
    renders_one :actions, ->(**attributes) { Actions.new(**attributes) }
    renders_one :trigger, ->(**attributes) { Trigger.new(**attributes) }

    STATES = %i[ready uploading processing error uploaded].freeze
    STATE_ALIASES = { idle: :ready, done: :uploaded }.freeze
    DEFAULT_ICONS = {
      ready: "clock",
      uploading: "loader-circle",
      processing: "file-text",
      error: "file-exclamation-point",
      uploaded: "check"
    }.freeze
    SIZES = %i[xs sm default].freeze
    ORIENTATIONS = %i[horizontal vertical].freeze

    def initialize(title:, description: nil, state: :ready, size: :default,
                   orientation: :horizontal, progress: nil, class: nil, **attributes)
      @title = title
      @description = description
      @state = normalize_state(state)
      @size = SIZES.include?(size) ? size : :default
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :horizontal
      @progress = normalize_progress(progress)
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("panel-attachment", @class),
        data: data.merge(
          state: @state,
          size: @size,
          orientation: @orientation,
          interactive: (trigger? ? "true" : nil)
        ).compact
      )
    end

    def default_icon = DEFAULT_ICONS.fetch(@state)

    def display_description
      return @description if @description.present?

      case @state
      when :ready then "Ready to upload"
      when :uploading then @progress.nil? ? "Uploading" : "Uploading · #{display_progress}%"
      when :processing then "Processing"
      when :error then "Upload failed. Try again."
      when :uploaded then "Uploaded"
      end
    end

    private

    def normalize_state(state)
      value = state.respond_to?(:to_sym) ? state.to_sym : nil
      value = STATE_ALIASES.fetch(value, value)
      STATES.include?(value) ? value : :ready
    end

    def normalize_progress(progress)
      return if progress.nil?

      Float(progress).clamp(0, 100)
    rescue ArgumentError, TypeError
      raise ArgumentError, "progress must be numeric"
    end

    def display_progress
      @progress.modulo(1).zero? ? @progress.to_i : @progress
    end
  end
end
