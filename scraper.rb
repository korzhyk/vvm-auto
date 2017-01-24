require 'scraperwiki'
require 'mechanize'

$site_url = "http://vvm-auto.ru"

def parse_page(url, data={})
  return if url.nil?
  p "Parsing #{data[:type]} from #{url}"
  agent = Mechanize.new
  page = agent.get("#{$site_url}#{url}")
  annotations = page.search('#content [itemprop="blogPost"]')
  annotations.each do |annotation|
    url = annotation.search('a').first.attribute('href').value
    id = /\/(\d+)-/.match(url)[1].to_i

    begin
      article = ScraperWiki.select('* FROM data WHERE id = ? LIMIT 1', [id]).first
      return unless article.nil?
    rescue => error
      p "Database error: #{error.to_s}"
    end

    title = annotation.search('a').first.child.content.strip
    annotation_text = annotation.search('p').length ? annotation.search('p').first.child.content : nil
    annotation_image = annotation.search('[itemprop="thumbnailUrl"]').length ? annotation.search('[itemprop="thumbnailUrl"]').attribute('src').value : nil
    data.merge!({
      id: id,
      title: title,
      annotation_text: annotation_text,
      annotation_image: "#{$site_url}#{annotation_image}",
      url: "#{$site_url}#{url}"
    })
    parse_article("#{$site_url}#{url}", data)
    ScraperWiki.save_sqlite([:id], data)
    p "#{data[:id]} - #{data[:title]} - #{data[:url]}"
  end
  next_page_links = page.search('span.icon-next')

  if next_page_links.length
    net_page_url = next_page_links.first.parent.attribute('href')
    p "Go to next page #{net_page_url}"
    parse_page(net_page_url, type: data[:type]) 
  end

end

def parse_article(url, data={})
  return if url.nil?
  agent = Mechanize.new
  page = agent.get(url)

  content = page.search('[itemprop="articleBody"]').first
  content.search('div.custom').each { |d| d.remove }
  content.search('*').each do |c|
    c.remove if c.blank?
    c.attributes.clear
  end
  content.search('img').each do |i|
    i.attribute('src').value = $site_url + i.attribute('src').value
  end

  data.merge!({
    content: content.to_s
  })
end

{
  experience: "opyt-ekspluatatsii",
  articles: "publikatsii",
  tests: "test-obzor"
}.each do |type, url|
  p "[debug] Load #{type} from #{url}"
  
  parse_page("/" << url, type: type.to_s)
end
