class Admin::ActivityLogsController < Admin::BaseController
  def index
    query = ActivityLogQuery.new(params)
    @tab = query.tab
    @tab_counts = ActivityLogQuery::TABS.keys.index_with { |name| ActivityLogQuery.model(name).count }
    @hotel_choices = Hotel.order(:name).pluck(:name, :id)
    @pagy, records = pagy(:offset, query.call, limit: 25)
    @rows = records.map { |record| ActivityLogRow.for(@tab, record) }
  end

  def show
    @tab = ActivityLogQuery.tab(params)
    @row = ActivityLogRow.for(@tab, ActivityLogQuery.model(@tab).find(params[:id]))
  end
end
