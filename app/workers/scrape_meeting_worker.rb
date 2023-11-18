class ScrapeMeetingWorker 
  include Sidekiq::Worker

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)

    pdfs = get_printed_minutes(meeting.url)
    pdfs.each do |pdf|
      document = meeting.documents.find_or_create_by!(url: pdf)
      document.update!(is_minutes: true)
      document.extract_text!
    end

    pdfs = recursive_get_pdfs(meeting.url)
    pdfs.each do |pdf|
      document = meeting.documents.find_or_create_by!(url: pdf)
      document.update!(is_minutes: false)
      document.extract_text!
    end
  end

  def get_printed_minutes(url)
    return nil if !url.start_with?('http')
    sleep CouncilScraper::GLOBAL_DELAY

    base_domain = 'https://' + URI(url).host

    doc = get_doc(url)
    links = doc.css('.mgContent a, .mgActionList a')
      .select do |link| 
        link.content.downcase.include?('printed minutes') || link.content.downcase.include?('printed draft minutes') 
      end
      .map { |link| link['href'] }.compact.uniq

    if links.length > 1
      puts "FOUND IT"
    end

    links.map do |link| 
      clean_link = link.gsub(' ', '+')
      begin
        URI.join(base_domain, clean_link).to_s 
      rescue URI::InvalidURIError
        nil
      end
    end.compact
  end

  def recursive_get_pdfs(url, depth = 0)
    sleep CouncilScraper::GLOBAL_DELAY

    return [] if !url.start_with?('http')
    puts "fetching #{url}"
    base_domain = 'https://' + URI(url).host
    doc = get_doc(url)
    links = doc.css('.mgContent a, .mgLinks a').map { |link| link['href'].to_s }.compact.uniq.map do |link| 
      clean_link = link.gsub(' ', '+')
      begin
        URI.join(base_domain, clean_link).to_s 
      rescue URI::InvalidURIError
        nil
      end
    end.compact
    pp links
    links.map do |link|
      main_url = link.split('?')[0]
      if main_url.downcase.ends_with?('.pdf') || main_url.downcase.ends_with?('.doc') || main_url.downcase.ends_with?('.docx')
        puts link
        link
      elsif depth < 2 && !link.include?('mgMeetingAttendance.aspx') && !link.include?('mgLocationDetails.aspx') && !link.include?('mgIssueHistoryHome.aspx') && !link.include?('mgIssueHistoryChronology.aspx') && !link.include?('ieIssueDetails.aspx')
        recursive_get_pdfs(link, depth+1)
      else
        []
      end
    end.flatten.uniq
  end

  def get_doc(url)
    uri = URI(url)
    host = uri.host
    response = Net::HTTP.get_response(uri)
    Nokogiri::HTML(response.body)
  end
end
