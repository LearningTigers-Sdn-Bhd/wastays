# frozen_string_literal: true

module PublicUI
  module Chat
    class SecureInput < PublicUI::BaseComponent
      def initialize(url:, kind:, error: nil)
        @url = url
        @kind = kind.to_sym
        @error = error
      end

      private

      attr_reader :url, :kind, :error

      def parameter = :confirmation_token
      def label = "Booking confirmation code"
      def hint = "You can find this code in your booking email."

      def input_attributes
        { autocapitalize: "characters", autocomplete: "off", maxlength: 64 }
      end
    end
  end
end
