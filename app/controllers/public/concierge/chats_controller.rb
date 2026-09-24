module Public
  module Concierge
    # The guest side of the message desk.
    #
    # This is a page the hotel owns, so a staff reply reaches the guest without
    # any outbound integration: the browser is already connected. That is the
    # whole reason the web chat comes before WhatsApp.
    class ChatsController < BaseController
      include ConciergeChatSession

      # The one screen the guest-chat switch closes. The rest of the concierge
      # page is gated a level up, in BaseController.
      before_action :ensure_guest_chat_available
      before_action :remember_return_to, only: :show

      helper_method :chat_back_path, :chat_back_label

      RETURN_TO_SESSION_KEY = :concierge_chat_return_to

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
            redirect_to concierge_chat_path(@hotel.unique_id, @hotel.public_id)
          end
        end
      end

      # Put away, not erased. The thread closes, the hotel keeps the transcript,
      # and the guest's next message opens a fresh one -- so this is a plain
      # redirect rather than a stream: there is nothing left on the page worth
      # keeping in place.
      def destroy
        ::Concierge::ClearConversation.new(conversation: current_conversation).call

        redirect_to concierge_chat_path(@hotel.unique_id, @hotel.public_id)
      end

      # The guest asks for a person. The assistant carries on answering while
      # they wait -- see Concierge::RequestHumanAgent for why that is not a
      # handover.
      def request_agent
        ::Concierge::RequestHumanAgent.new(
          conversation: current_conversation,
          reason: params[:reason]
        ).call

        redirect_to concierge_chat_path(@hotel.unique_id, @hotel.public_id)
      end

      private

      # The page that opened the chat, so the back button returns there. Kept
      # in the session because every send, clear and hand-off redirects back
      # to the chat, and none of those forms carry it.
      def remember_return_to
        return if params[:return_to].blank?

        session[RETURN_TO_SESSION_KEY] = safe_return_to(params[:return_to].to_s)
      end

      # Only a page of this hotel's concierge, so the chat cannot be turned
      # into an open redirect.
      def safe_return_to(candidate)
        home = concierge_home_path(@hotel.unique_id, @hotel.public_id)
        path = candidate.split("?").first.to_s
        return candidate if path == home || path.start_with?("#{home}/")

        nil
      end

      def chat_back_path
        safe_return_to(session[RETURN_TO_SESSION_KEY].to_s) ||
          concierge_home_path(@hotel.unique_id, @hotel.public_id)
      end

      def chat_back_label
        stay_prefix = "#{concierge_home_path(@hotel.unique_id, @hotel.public_id)}/stay/"
        chat_back_path.start_with?(stay_prefix) ? "Back to your stay" : "Back"
      end

      def ensure_guest_chat_available
        return if @hotel&.concierge_chat_available?

        redirect_to concierge_home_path(@hotel.unique_id, @hotel.public_id)
      end

      # A write hands over the thread it wrote into -- on a first message that is
      # a conversation the cookie does not know about yet, so looking it up again
      # would find nothing.
      def load_thread(conversation = nil)
        @conversation = conversation || current_conversation
        @messages = @conversation ? @conversation.messages.includes(:sender_user).to_a : []
        @chat_input = ::Concierge::ChatInputPresenter.new(conversation: @conversation, error: @error)
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
