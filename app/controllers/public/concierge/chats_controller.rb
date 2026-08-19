module Public
  module Concierge
    # The guest side of the message desk.
    #
    # This is a page the hotel owns, so a staff reply reaches the guest without
    # any outbound integration: the browser is already connected. That is the
    # whole reason the web chat comes before WhatsApp.
    class ChatsController < BaseController
      include ConciergeChatSession

      def show
        @conversation = current_conversation
        @messages = @conversation ? @conversation.messages.to_a : []
      end

      def create
        result = ::Concierge::PostWebMessage.new(
          hotel: @hotel,
          message: params[:message],
          prospect_public_id: current_chat_prospect_public_id
        ).call

        set_chat_prospect_cookie(result.prospect) if result.prospect
        flash[:alert] = result.error if result.error.present?

        redirect_to concierge_chat_path(@hotel)
      end

      private

      def current_conversation
        public_id = current_chat_prospect_public_id
        return nil if public_id.blank?

        prospect = @hotel.prospects.includes(:conversations).find_by(public_id: public_id)
        prospect&.conversations&.open&.find_by(channel: ::Concierge::PostWebMessage::CHANNEL)
      end
    end
  end
end
