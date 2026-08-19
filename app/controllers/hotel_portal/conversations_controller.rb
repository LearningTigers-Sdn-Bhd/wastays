# frozen_string_literal: true

module HotelPortal
  # The guest message desk. Read-only for now: staff can see every thread the
  # bot is holding, which is the thing they could not do at all before. Replying
  # waits for a delivery path -- a reply typed here today would reach nobody.
  class ConversationsController < HotelPortal::BaseController
    before_action :authorize_manage_concierge!
    before_action :set_conversations
    before_action :set_conversation, only: :show

    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    def index; end

    # Opening a thread is what marks it read, so the unread count means "nobody
    # has looked at this" rather than "nobody has answered it".
    def show
      @conversation.messages.unread.from_guest.update_all(read_at: Time.current)
    end

    private

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

    def authorize_manage_concierge!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_concierge", hotel: current_hotel)
    end

    def handle_record_not_found
      redirect_to hotel_conversations_path(current_hotel), alert: "That conversation could not be found."
    end
  end
end
