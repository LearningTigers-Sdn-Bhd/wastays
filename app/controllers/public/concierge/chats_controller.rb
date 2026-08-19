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
        load_thread
      end

      # Answered in place. A guest who has just typed a question should not
      # watch the page they are reading rebuild itself around the answer, and on
      # a phone a full reload is a visible flash and a lost keyboard.
      #
      # The redirect stays as the reply to a browser that asked for HTML, so the
      # chat still works with no JavaScript at all.
      def create
        result = ::Concierge::PostWebMessage.new(
          hotel: @hotel,
          message: params[:message],
          prospect_public_id: current_chat_prospect_public_id
        ).call

        set_chat_prospect_cookie(result.prospect) if result.prospect
        @error = result.error
        load_thread(result.conversation)

        respond_to do |format|
          format.turbo_stream { render :create }
          format.html do
            flash[:alert] = @error if @error.present?
            redirect_to concierge_chat_path(@hotel)
          end
        end
      end

      # Put away, not erased. The thread closes, the hotel keeps the transcript,
      # and the guest's next message opens a fresh one -- so this is a plain
      # redirect rather than a stream: there is nothing left on the page worth
      # keeping in place.
      def destroy
        ::Concierge::ClearConversation.new(conversation: current_conversation).call

        redirect_to concierge_chat_path(@hotel)
      end

      # The guest asks for a person. The assistant carries on answering while
      # they wait -- see Concierge::RequestHumanAgent for why that is not a
      # handover.
      def request_agent
        ::Concierge::RequestHumanAgent.new(conversation: current_conversation).call

        redirect_to concierge_chat_path(@hotel)
      end

      private

      # A write hands over the thread it wrote into -- on a first message that is
      # a conversation the cookie does not know about yet, so looking it up again
      # would find nothing.
      def load_thread(conversation = nil)
        @conversation = conversation || current_conversation
        @messages = @conversation ? @conversation.messages.reload.to_a : []
      end

      def current_conversation
        public_id = current_chat_prospect_public_id
        return nil if public_id.blank?

        prospect = @hotel.prospects.includes(:conversations).find_by(public_id: public_id)
        prospect&.conversations&.open&.find_by(channel: ::Concierge::PostWebMessage::CHANNEL)
      end
    end
  end
end
