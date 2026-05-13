# frozen_string_literal: true

require "ostruct"

module Rooms
  class ManageBlock
    def initialize(hotel:, user:, params: nil, block: nil)
      @hotel = hotel
      @user = user
      @params = params
      @block = block
    end

    def create
      @block = @hotel.room_blocks.build(@params)
      @block.user = @user

      if @block.save
        sync_room_status if @block.active_on?(Date.current)
        success(@block)
      else
        failure(@block.errors.full_messages.to_sentence)
      end
    end

    def update
      return failure("Block not found") unless @block

      was_active_today = @block.active_on?(Date.current)

      if @block.update(@params)
        is_active_today = @block.active_on?(Date.current)
        
        if is_active_today
          sync_room_status
        elsif was_active_today && !is_active_today
          sync_room_status_on_removal(@block.room_type, @block.room_number)
        end
        
        success(@block)
      else
        failure(@block.errors.full_messages.to_sentence)
      end
    end

    def destroy
      return failure("Block not found") unless @block

      # Capture details before destruction for sync check
      room_type = @block.room_type
      room_number = @block.room_number
      was_active_today = @block.active_on?(Date.current)

      if @block.destroy
        sync_room_status_on_removal(room_type, room_number, target_status: "ready") if was_active_today
        success(@block)
      else
        failure(@block.errors.full_messages.to_sentence)
      end
    end

    def finish
      return failure("Block not found") unless @block

      was_active_today = @block.active_on?(Date.current)

      # Record completion time
      @block.completed_at = Time.current

      if @block.save
        sync_room_status_on_removal(@block.room_type, @block.room_number, target_status: "pending_cleaning") if was_active_today
        success(@block)
      else
        failure(@block.errors.full_messages.to_sentence)
      end
    end

    private

    def sync_room_status
      room_status = @hotel.room_statuses.find_or_create_by!(
        room_type: @block.room_type,
        room_number: @block.room_number
      )

      Rooms::SetStatus.new(
        room_status: room_status,
        status: "out_of_service",
        user: @user,
        reason: "Blocked: #{@block.block_type} (#{@block.reason})",
        event_type: "room_blocked_auto_status"
      ).call
    end

    def sync_room_status_on_removal(room_type, room_number, target_status: "ready")
      # Check if there are other active blocks for this room today (excluding the one we just finished/removed)
      other_blocks = @hotel.room_blocks.active_on(Date.current)
                           .where(room_type: room_type, room_number: room_number)
                           .where.not(id: @block&.id)
      
      return if other_blocks.any?

      room_status = @hotel.room_statuses.find_by(
        room_type: room_type,
        room_number: room_number
      )

      return unless room_status && room_status.status == "out_of_service"

      Rooms::SetStatus.new(
        room_status: room_status,
        status: target_status,
        user: @user,
        reason: "Block removed/expired",
        event_type: "room_block_removed_auto_status"
      ).call
    end

    def success(block)
      OpenStruct.new(success?: true, block: block)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
