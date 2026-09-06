module Admin
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "admin"
    before_action :authenticate_superadmin!

    private

    def pagy_offset(collection, limit:, page_key: "page")
      page = Integer(params[page_key], exception: false).to_i
      pagy(
        :offset,
        collection,
        limit: limit,
        page_key: page_key,
        page: page.positive? ? page : 1
      )
    end
  end
end
