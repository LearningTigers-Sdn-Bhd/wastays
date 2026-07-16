# frozen_string_literal: true

module PanelsUI
  class Dropzone < PanelsUI::BaseComponent
    PREVIEWS = %i[auto icon image].freeze

    def initialize(form:, attribute:, id: nil, accept: nil, multiple: false,
                   max_files: nil, max_size: nil, existing_count: 0, preview: :auto,
                   prompt: "Drop files here or", description: nil,
                   described_by: nil, labelled_by: nil, invalid: false, required: false,
                   disabled: false, size: :md, class: nil, **input_attributes)
      @form = form
      @attribute = attribute
      @id = id || @form.field_id(@attribute)
      @accept = accept
      @multiple = multiple
      @max_files = normalize_max_files(max_files)
      @max_size = normalize_non_negative_integer(max_size, :max_size)
      @existing_count = normalize_non_negative_integer(existing_count, :existing_count)
      @preview = PREVIEWS.include?(preview) ? preview : :auto
      @prompt = prompt
      @description = description
      @described_by = described_by
      @labelled_by = labelled_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @size = FormField::SIZES.include?(size) ? size : :md
      @class = binding.local_variable_get(:class)
      @input_attributes = input_attributes
    end

    def root_attributes
      {
        class: tw_merge("panel-dropzone", @class),
        data: {
          controller: "panels-ui--dropzone",
          action: dropzone_actions,
          panels_ui__dropzone_accept_value: @accept,
          panels_ui__dropzone_multiple_value: @multiple,
          panels_ui__dropzone_max_files_value: @max_files,
          panels_ui__dropzone_max_size_value: @max_size,
          panels_ui__dropzone_existing_count_value: @existing_count,
          panels_ui__dropzone_preview_value: @preview,
          size: @size,
          invalid: @invalid.to_s,
          disabled: @disabled.to_s
        }.compact,
        role: "group",
        aria: { labelledby: @labelled_by }.compact
      }
    end

    def input_attributes
      attributes = @input_attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), @described_by, client_error_id ].compact.join(" ")
      caller_action = data.delete(:action) || data.delete("action")

      attributes.merge(
        id: @id,
        accept: @accept,
        multiple: @multiple,
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        class: tw_merge("sr-only", attributes.delete(:class)),
        data: data.merge(
          panels_ui__dropzone_target: "input",
          action: [ caller_action, "change->panels-ui--dropzone#select" ].compact.join(" ")
        ),
        aria: aria.merge(describedby: described_by, invalid: (@invalid ? "true" : nil)).compact
      ).compact
    end

    def client_error_id = "#{@id}-dropzone-error"

    private

    def normalize_max_files(value)
      return 1 unless @multiple
      return if value.nil?

      normalized = Integer(value)
      raise ArgumentError, "max_files must be greater than zero" unless normalized.positive?

      normalized
    rescue ArgumentError, TypeError => error
      raise error if error.message == "max_files must be greater than zero"

      raise ArgumentError, "max_files must be an integer"
    end

    def normalize_non_negative_integer(value, name)
      return if value.nil? && name == :max_size

      normalized = Integer(value || 0)
      raise ArgumentError, "#{name} must not be negative" if normalized.negative?

      normalized
    rescue ArgumentError, TypeError => error
      raise error if error.message == "#{name} must not be negative"

      raise ArgumentError, "#{name} must be an integer"
    end

    def dropzone_actions
      %w[
        dragenter->panels-ui--dropzone#dragenter
        dragover->panels-ui--dropzone#dragover
        dragleave->panels-ui--dropzone#dragleave
        drop->panels-ui--dropzone#drop
        reset@document->panels-ui--dropzone#reset
      ].join(" ")
    end
  end
end
