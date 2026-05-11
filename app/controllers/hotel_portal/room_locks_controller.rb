# frozen_string_literal: true

class HotelPortal::RoomLocksController < HotelPortal::BaseController
  def create
    Rails.logger.info "[ROOM LOCK CONTROLLER] Params: #{params.inspect}"
    RoomLock.cleanup_expired!

    # Try to find an existing lock for this room
    lock = RoomLock.find_by(hotel: current_hotel, room_type_id: params[:room_type_id], room_number: params[:room_number])

    if lock
      if lock.user == current_user
        # Admin already holds the lock, refresh it
        lock.refresh!
        render json: { status: "success", message: "Lock refreshed" }
      else
        # Lock held by someone else
        render json: {
          status: "locked",
          message: "Room #{params[:room_number]} is currently being assigned by #{lock.user.name}"
        }, status: :conflict
      end
    else
      # Create new lock
      lock = RoomLock.new(
        hotel: current_hotel,
        user: current_user,
        room_type_id: params[:room_type_id],
        room_number: params[:room_number],
        expires_at: Time.current + 10.minutes
      )

      if lock.save
        render json: { status: "success", message: "Room locked" }, status: :created
      else
        render json: { status: "error", message: lock.errors.full_messages.to_sentence }, status: :unprocessable_content
      end
    end
  end

  def release
    lock = RoomLock.find_by(hotel: current_hotel, room_type_id: params[:room_type_id], room_number: params[:room_number], user: current_user)

    if lock&.destroy
      render json: { status: "success", message: "Lock released" }
    else
      render json: { status: "not_found", message: "No active lock found for this room" }, status: :not_found
    end
  end
end
