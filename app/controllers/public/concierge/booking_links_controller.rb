# frozen_string_literal: true

module Public
  module Concierge
    class BookingLinksController < BaseController
      include ConciergeChatSession

      before_action :ensure_guest_chat_available
      before_action :load_conversation

      def create
        result = ::Concierge::SendBookingMagicLink.new(
          hotel: @hotel,
          conversation: @conversation,
          confirmation_token: params[:confirmation_token]
        ).call
        render_result(result)
      end

      private

      def ensure_guest_chat_available
        return if @hotel&.concierge_chat_available?

        redirect_to concierge_home_path(@hotel)
      end

      def load_conversation
        public_id = current_chat_prospect_public_id
        prospect = @hotel.prospects.find_by(public_id: public_id)
        @conversation = prospect&.conversations&.open&.find_by(channel: ::Concierge::PostWebMessage::CHANNEL)
        head :not_found unless @conversation
      end

      def render_result(result)
        error = result.success? ? nil : result.error
        input = ::Concierge::ChatInputPresenter.new(conversation: @conversation, error: error)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              PublicUI::Chat::Panel::INPUT_REGION_ID,
              partial: "public/concierge/chats/input",
              locals: { hotel: @hotel, input: input }
            )
          end
          format.html do
            flash[:alert] = error if error.present?
            redirect_to concierge_chat_path(@hotel)
          end
        end
      end
    end
  end
end
