# frozen_string_literal: true

module GuestUI
  # One photo a guest adds: the front of an IC, a passport page.
  #
  # On a touch screen the button opens a sheet: Take a photo, or Choose a
  # photo or file. A phone's own menu cannot be relied on for that choice --
  # an iPhone shows one, but Android 14 and later go straight to the photo
  # picker. Take a photo sets `capture`, so the phone's own camera opens;
  # Choose clears it. With a mouse the button opens the file dialog.
  #
  # The sheet is a native <dialog> run by concierge-modal, the concierge's
  # bottom-sheet controller, so it has Esc, the backdrop and the scroll lock.
  #
  # The input is hidden from sight but not from the form, so the browser can
  # still point at it when a `required` photo is missing.
  class ImageUpload < GuestUI::BaseComponent
    def initialize(form:, attribute:, label:, hint: "Photo, gallery or file", icon: "id-card",
                   preview_url: nil, required: false, disabled: false, error: nil, id: nil,
                   class: nil, **attributes)
      @form = form
      @attribute = attribute
      @label = label
      @hint = hint
      @icon = icon
      @preview_url = preview_url
      @required = required
      @disabled = disabled
      @error = error
      @id = id
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def input_id = @id || @form.field_id(@attribute)
    def sheet_title_id = "#{input_id}-sheet-title"
    def label_id = "#{input_id}-label"
    def hint_id = "#{input_id}-hint"
    def error_id = "#{input_id}-error"
    def filled? = @preview_url.present?

    private

    attr_reader :label, :hint, :icon, :error

    def described_by = [ hint_id, (error_id if error.present?) ].compact.join(" ")

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-image-upload", @class),
        data: data.merge(controller: "guest-image-upload concierge-modal", state: (filled? ? "filled" : "empty"),
                         invalid: error.present?.to_s)
      )
    end

    def file_input
      @form.file_field(@attribute,
        id: input_id,
        accept: "image/*",
        class: "guest-image-upload__input",
        tabindex: "-1",
        required: (@required && !filled?),
        disabled: @disabled,
        aria: { hidden: "true" },
        data: { guest_image_upload_target: "input", action: "change->guest-image-upload#changed" })
    end
  end
end
