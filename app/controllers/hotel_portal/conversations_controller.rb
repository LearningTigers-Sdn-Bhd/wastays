# frozen_string_literal: true

module HotelPortal
  # The guest message desk: read the threads the bot is holding, and take one
  # over when the answer needs a person.
  #
  # Every write answers in Turbo Streams, not a redirect. Reloading the whole
  # inbox to show one new bubble throws away the reader's scroll position and
  # anything half-typed in the box, which is the wrong trade on a screen someone
  # sits in front of all day. The message itself is not in the response: it is
  # already on its way down the staff stream, and the reader is subscribed.
  #
  # A browser without JavaScript still gets the redirect, so nothing here is
  # only reachable through Turbo.
  class ConversationsController < HotelPortal::BaseController
    WRITES = %i[reply take_over return_to_bot close reopen].freeze

    before_action :authorize_manage_concierge!
    before_action :set_conversations, only: %i[index show]
    before_action :set_conversation, only: [ :show, *WRITES ]

    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    def index; end

    # Opening a thread is what marks it read, so the unread count means "nobody
    # has looked at this" rather than "nobody has answered it".
    def show
      marked = @conversation.messages.unread.from_guest.update_all(read_at: Time.current)

      # update_all runs no callbacks, so the row and the unread count would sit
      # there claiming this thread is still waiting on somebody.
      @conversation.broadcast_to_inbox if marked.positive?
    end

    def reply
      result = ::Concierge::PostStaffReply.new(
        conversation: @conversation,
        user: current_user,
        body: params[:body]
      ).call

      respond_to_write(alert: result.error)
    end

    def take_over
      ::Concierge::TakeOverConversation.new(conversation: @conversation, user: current_user).call
      respond_to_write(notice: "You are holding this conversation now.")
    end

    def return_to_bot
      unless current_hotel.ai_concierge_ready?
        return respond_to_write(alert: "The assistant is not switched on for this hotel.")
      end

      ::Concierge::ReturnConversationToBot.new(conversation: @conversation).call
      respond_to_write(notice: "The assistant is answering this conversation again.")
    end

    def close
      @conversation.close!
      respond_to_write(notice: "Conversation closed.")
    end

    def reopen
      @conversation.reopen!
      respond_to_write(notice: "Conversation reopened.")
    end

    private

    # One shape for every write: the card tells the reader what it can do next,
    # and the same words reach a browser that asked for HTML as a flash.
    def respond_to_write(notice: nil, alert: nil)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          @conversation.reload
          render :thread_update
        end
        format.html { redirect_to_thread(notice: notice, alert: alert) }
      end
    end

    def set_conversations
      @query = ConversationsQuery.new(hotel: current_hotel, params: params)
      @conversations = @query.call.page(params[:page]).per(30)
      @counts = @query.counts
    end

    def set_conversation
      @conversation = Conversation.for_hotel(current_hotel)
                                  .includes(:assigned_user, prospect: :guest)
                                  .find(params[:id])
      @messages = @conversation.messages.includes(:sender_user).to_a
    end

    def redirect_to_thread(notice: nil, alert: nil)
      redirect_to hotel_conversation_path(current_hotel, @conversation), notice: notice, alert: alert
    end

    def authorize_manage_concierge!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_concierge", hotel: current_hotel)
    end

    def handle_record_not_found
      redirect_to hotel_conversations_path(current_hotel), alert: "That conversation could not be found."
    end
  end
end
