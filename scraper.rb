require 'scraperwiki'
require 'mechanize'
require 'nokogiri'
require 'reverse_markdown'

$agent = Mechanize.new
$site_url = "http://vvm-auto.ru"
$image_scraped = nil


def parse_pages(url, data={})
  p "[debug] Parsing #{data[:type]} from #{url}"
  page = $agent.get(url)
  next_page_link = page.search('span.icon-next').length ? page.search('span.icon-next').first.parent.attribute('href').value : nil
  parse_page(data)
  unless true || next_page_link.nil?
    p "[debug] Go to next page #{next_page_link}"
    parse_pages($agent.resolve(next_page_link), data) 
  end
end

def parse_page(data={})
  page = $agent.page
  posts = page.search('#content [itemprop="blogPost"]')
  posts.each do |post|
    link_to_post = post.search('a').first
    url = $agent.resolve(link_to_post.attribute('href'))
    id = /\/(\d+)-/.match(url.to_s)[1].to_i

    begin
      article = ScraperWiki.select('* FROM data WHERE id = ? LIMIT 1', [id]).first
      next unless article.nil?
    rescue => error
      p "Database error: #{error.to_s}"
    end

    title = post.search('a').first.child.content.strip
    annotation_text = post.search('p').first.nil? ? nil : post.search('p').first.child.content
    annotation_image = post.search('[itemprop="thumbnailUrl"]').first.nil? ? nil : post.search('[itemprop="thumbnailUrl"]').attribute('src').value

    data.merge!({
      id: id,
      title: title,
      annotation_text: ReverseMarkdown.convert(annotation_text),
      annotation_image: "#{$site_url}#{annotation_image}",
      url: url.to_s
    })
    $agent.get(url)
    parse_article(data)
    ScraperWiki.save_sqlite([:id], data)
    p "[debug] Article with id = #{data[:id]} was parsed, full link: #{url}"
    sleep 5
  end
end

def parse_article(data={})
  #agent = Mechanize.new
  page = $agent.page #$agent.get(url)

  content = page.search('[itemprop="articleBody"]').first
  content.search('div.custom').each { |d| d.remove }
  content.search('img').each do |i|
    i['src'] = $agent.resolve(i['src']).to_s
    scraped = scrape_image(i['src'])
    i.remove unless scraped
  end

  remove_empty(content)

  html = content.to_xhtml.strip
  md = ReverseMarkdown.convert(html)
  
  data.merge!({
    html: html,
    md: md
  })
end

def remove_empty(node)
  unless node.children.empty?
    node.children.each { |c| remove_empty(c) }  
  end
  # p "==========================================================================="
  if node.text? && node.blank?
    # p "remove text #{node.keys}"
    node.remove
  end
  
  if node.name != 'img' && !node['src'] && !node.text? && node.children.empty?
    # p "remove element #{node.name}"
    node.remove
  end  
  # p "Node [type:#{node.type} | text:#{node.text?} | element:#{node.element?} | fragment:#{node.fragment?}]"
  # p "Node [blank:#{node.blank?} | empty:#{node.children.empty?} | read_only:#{node.read_only?}] #{node}"
end

def scrape_image(url)
  return nil unless url
  image = $agent.get_file(url)
  p "[debug] image #{url} fetched, size is: #{image.length}"
  ScraperWiki.save_sqlite([:url], { url: url.to_s, blob: image }, 'images').first
end


{
  experience: "opyt-ekspluatatsii",
  articles: "publikatsii",
  tests: "test-obzor"
}.each do |type, url|
  url = $site_url + "/" + url
  parse_pages(url, type: type.to_s)
end
