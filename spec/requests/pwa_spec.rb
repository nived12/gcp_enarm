require "rails_helper"

# Installability is what lets an iPhone receive Web Push at all, so the manifest is held
# to what Chrome and iOS check before they offer "Agregar a pantalla de inicio".
RSpec.describe "Installable web app", type: :request do
  it "serves a manifest with the name, standalone display and the icons installers need" do
    get pwa_manifest_path(format: :json)

    manifest = response.parsed_body
    expect(manifest).to include(
      "name" => "GPCEnarm", "start_url" => "/", "display" => "standalone",
      "theme_color" => "#fffcf5"
    )
    expect(manifest["icons"].map { |icon| [icon["sizes"], icon["purpose"]] })
      .to contain_exactly(%w[192x192 any], %w[512x512 any], %w[512x512 maskable])
    manifest["icons"].each { |icon| expect(Rails.public_path.join(icon["src"].delete_prefix("/"))).to exist }
  end

  it "links the manifest from every page" do
    get root_path

    expect(response.body).to include(%(<link rel="manifest" href="/manifest.json">))
  end

  it "serves a service worker that handles pushes and caches nothing" do
    get pwa_service_worker_path(format: :js)

    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to include('addEventListener("push"', 'addEventListener("notificationclick"')
    expect(response.body).not_to include('addEventListener("fetch"')
  end
end
