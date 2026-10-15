class Admin::NotificationLogsController < Admin::BaseController
  def index
    query = NotificationLogQuery.new(params)
    @tab = query.tab
    @tab_counts = {
      "whatsapp" => NotificationDelivery.where(channel: "whatsapp").count,
      "staff" => StaffNotification.count
    }
    @pagy, @notifications = pagy(:offset, query.call, limit: 25)
  end

  def show
    @tab = NotificationLogQuery.tab(params)
    @notification = @tab == "staff" ? StaffNotification.find(params[:id]) : NotificationDelivery.where(channel: "whatsapp").find(params[:id])
  end
end
