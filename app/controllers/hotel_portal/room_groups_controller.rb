# frozen_string_literal: true

class HotelPortal::RoomGroupsController < HotelPortal::BaseController
  before_action :set_hotel
  before_action :authorize_hotel
  before_action :set_room_group, only: [ :edit, :update, :destroy ]

  def index
    @room_groups = @hotel.room_groups.includes(:room_types).order(:name)
    @room_group = @hotel.room_groups.build
  end

  def create
    @room_group = @hotel.room_groups.build(room_group_params)

    if @room_group.save
      respond_to do |format|
        format.html { redirect_to hotel_room_groups_path(@hotel), notice: "Room group created successfully." }
        format.turbo_stream { render turbo_stream: turbo_stream.append("offcanvas_drawer", html: "<script>window.location.reload();</script>".html_safe) }
      end
    else
      @room_groups = @hotel.room_groups.includes(:room_types).order(:name)
      render :index, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @room_group.update(room_group_params)
      respond_to do |format|
        format.html { redirect_to hotel_room_groups_path(@hotel), notice: "Room group updated successfully." }
        format.turbo_stream { render turbo_stream: turbo_stream.append("offcanvas_drawer", html: "<script>window.location.reload();</script>".html_safe) }
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @room_group.destroy
      respond_to do |format|
        format.html { redirect_to hotel_room_groups_path(@hotel), notice: "Room group deleted successfully." }
        format.turbo_stream { render turbo_stream: turbo_stream.append("offcanvas_drawer", html: "<script>window.location.href = '#{hotel_room_types_path(@hotel)}';</script>".html_safe) }
      end
    else
      respond_to do |format|
        format.html { redirect_to hotel_room_groups_path(@hotel), alert: "Cannot delete room group." }
        format.turbo_stream { render turbo_stream: turbo_stream.append("offcanvas_drawer", html: "<script>alert('Cannot delete room group.');</script>".html_safe) }
      end
    end
  end

  private

  def set_hotel
    @hotel = current_hotel
  end

  def authorize_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy
  end

  def set_room_group
    @room_group = @hotel.room_groups.find(params[:id])
  end

  def room_group_params
    params.require(:room_group).permit(:name)
  end
end
