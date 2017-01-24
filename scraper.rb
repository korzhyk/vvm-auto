require 'scraperwiki'
require 'mechanize'

$site_url = "http://vvm-auto.ru"

def parse_page(url, data={})
  return if url.nil?
  agent = Mechanize.new
  page = agent.get("#{$site_url}/#{url}")
  annotations = page.search('#content [itemprop="blogPost"]')
  annotations.each do |annotation|
    url = annotation.search('a').first.attribute('href').value
    id = /\/(\d+)-/.match(url)[1].to_i

    article = ScraperWiki.select('WHERE id = ?', id)
    p article.to_s

    title = annotation.search('a').first.child.content.strip
    annotation_text = annotation.search('p').try(:first) { |p| p ? p.child.content : nil  }
    annotation_image = annotation.search('[itemprop="thumbnailUrl"]').try(:first) { |i| i.attribute('src').value ? nil  }
    data.merge!({
      id: id,
      title: title,
      annotation_text: annotation_text,
      annotation_image: "#{$site_url}#{annotation_image}",
      url: url
    })
    parse_article("#{$site_url}#{url}", data)
    ScraperWiki.save_sqlite([data[:id]], data)
    p "#{data[:id]} - #{data[:title]} - #{data[:url]}"
  end
  next_page_links = page.search('span.icon-next')

  parse_page(next_page_links.first.parent.attribute('href'), type: data[:type]) if next_page_links.length
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
  
  parse_page(url, type: type)
end
