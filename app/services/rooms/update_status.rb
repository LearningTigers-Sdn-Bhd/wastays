# frozen_string_literal: true

require "ostruct"

module Rooms
  class UpdateStatus
    def initialize(room_status:, params:, user:)
      @room_status = room_status
      @params = params
      @user = user
    end

    def call
      if @params.key?(:priority)
        @room_status.priority = @params[:priority]
      end

      if @params.key?(:notes)
        @room_status.notes = @params[:notes]
      end

      if @params.key?(:dnd)
        @room_status.dnd = ActiveRecord::Type::Boolean.new.cast(@params[:dnd])
        @room_status.dnd_date = @room_status.dnd ? @room_status.hotel.current_business_date : nil
      end

      if @params[:status].present? && @params[:status] != @room_status.status_was
        Rooms::SetStatus.new(
          room_status: @room_status,
          status: @params[:status],
          user: @user,
          reason: @params[:notes]
        ).call
      else
        if @room_status.save
          OpenStruct.new(success?: true)
        else
          OpenStruct.new(success?: false, error: @room_status.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
