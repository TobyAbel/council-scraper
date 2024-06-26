class ScrapeCouncilsWorker
  include Sidekiq::Worker

  def perform(num_weeks_back = 4)
    CSV.foreach('data/councils.csv', headers: true) do |row|
      council = Council.find_or_create_by!(external_id: row['id'], council_type: Council.modern_gov)
      council.update!(name: row['name'], base_scrape_url: row['url'])
    end

    CSV.foreach('data/cmis_councils.csv', headers: true) do |row|
      council = Council.find_or_create_by!(external_id: row['id'], council_type: Council.cmis)
      council.update!(name: row['name'], base_scrape_url: row['url'])
    end

    Council.order(Arel.sql('RANDOM()')).each do |council|
      (0..num_weeks_back).each do |weeks_ago|
        date = Date.today - (weeks_ago * 7)
        beginning_of_week = date.beginning_of_week(:monday)

        ScrapeCouncilWorker.perform_async(council.id, beginning_of_week.to_s)
      end

      ScrapeDecisionsWorker.perform_async(council.id)
    end
  end
end
