require 'scraperwiki'
require 'mechanize'

$site_url = "http://vvm-auto.ru"

def parse_page(url, data={})
  agent = Mechanize.new
  page = agent.get("#{$site_url}/#{url}")
  annotations = page.search('#content [itemprop="blogPost"]')
  annotations.each do |annotation|
    url = annotation.search('a').first.attribute('href').value
    title = annotation.search('a').first.child.content.strip
    annotation_text = annotation.search('p').first.child.content
    annotation_image = annotation.search('[itemprop="thumbnailUrl"]').first.attribute('src').value
    data.merge!({
      title: title,
      annotation_text: annotation_text,
      annotation_image: "#{$site_url}#{annotation_image}"
    })
    parse_article(url, data)
    #ScraperWiki.save_sqlite([data[:id]], data)
    p "#{data[:id]} - #{data[:title]} - #{data[:url]}"
  end
  next_page_links = page.search('span.icon-next')

  parse_page(next_page_links.first.parent.attribute('href'), type: data[:type]) if next_page_links.length
end

def parse_article(url, data={})
  id = /\/(\d+)-/.match(url)[1].to_i
  url = "#{$site_url}#{url}"
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
    id: id,
    content: content.to_s,
    url: url
  })
end

{
  experience: "opyt-ekspluatatsii",
  articles: "publikatsii",
  tests: "test-obzor"
}.each do |type, url|
  p "[debug] Load #{type} from #{url}"
  
  parse_page(url, type: type)
end
