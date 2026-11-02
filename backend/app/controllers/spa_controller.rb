# Sends the built React app (public/index.html) for "/" and deep links. See config/routes.rb.
class SpaController < ActionController::API
  def index
    index = Rails.public_path.join("index.html")
    return head :not_found unless index.exist?
    send_file index, type: "text/html", disposition: "inline"
  end
end
