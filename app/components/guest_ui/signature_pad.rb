# frozen_string_literal: true

module GuestUI
  # A signature, drawn with a finger or a mouse.
  #
  # Built like an input group: the pad and a footer bar share one frame. The
  # footer says whether the pad is signed and holds Clear, which is only
  # enabled once there is something to clear. The drawing goes into a hidden
  # field as a PNG data URL; the `signature` controller does both.
  class SignaturePad < GuestUI::BaseComponent
    def initialize(form:, attribute:, label: "Signature", required: false, error: nil, id: nil,
                   class: nil, **attributes)
      @form = form
      @attribute = attribute
      @label = label
      @required = required
      @error = error
      @id = id
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def field_id = @id || @form.field_id(@attribute)
    def label_id = "#{field_id}-label"
    def status_id = "#{field_id}-status"
    def error_id = "#{field_id}-error"

    private

    attr_reader :label, :error

    def described_by = [ status_id, (error_id if error.present?) ].compact.join(" ")

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-signature-pad", @class),
        data: data.merge(controller: "signature", invalid: error.present?.to_s)
      )
    end
  end
end
