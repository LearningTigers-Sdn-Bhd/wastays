module Admin
  class ObservationDeckController < Admin::BaseController
    before_action :authenticate_superadmin!

    def index
      @entries = ObservationEntry.all.order(created_at: :desc)

      if params[:entry_type].present?
        @entries = @entries.where(entry_type: params[:entry_type])
      end

      if params[:status].present?
        @entries = @entries.where(status: params[:status])
      end

      @entries = @entries.page(params[:page]).per(50)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @entry = ObservationEntry.find(params[:id])
      render layout: false
    end

    def clear
      ObservationEntry.delete_all
      redirect_to admin_observation_deck_index_path, notice: "Observation deck cleared."
    end
  end
end
