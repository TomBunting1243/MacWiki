import XCTest
@testable import MacWiki

final class InfoboxParsingTests: XCTestCase {
    
    // Test 1: Complex Attribute Skipping (The "Garbled" Bug)
    func testComplexAttributes() {
        // Construct HTML mimicking the "Alex Honnold" garbage issue
        // The issue was `> ...` being found inside `data-mw`.
        // Case: `data-mw="{\"parts\":[{\"template\":{\"target\":{\"wt\":\"married\",\"href\":\"./Template:Married\"},\"params\":{},\"i\":0}}]}"`
        // Note the nested quotes and strict JSON structure.
        
        let html = """
        <table class="infobox biography vcard">
            <tr>
                <th scope="row" class="infobox-label">Spouse</th>
                <td class="infobox-data" data-mw="{&quot;parts&quot;:[{&quot;template&quot;:{&quot;target&quot;:{&quot;wt&quot;:&quot;married&quot;,&quot;href&quot;:&quot;./Template:Married&quot;},&quot;params&quot;:{},&quot;i&quot;:0}}]}">Sanni McCandless</td>
            </tr>
        </table>
        """
        
        let items = InfoboxParser.extractMetadata(from: html)
        
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.label, "Spouse")
        
        // If parsing fails, we might see the JSON garbage here
        XCTAssertEqual(items.first?.value, "Sanni McCandless") 
    }
    
    // Test 2: Links with Parentheses (The Markdown Link Bug)
    func testLinksWithParentheses() {
        let html = """
        <table class="infobox">
            <tr>
                <th scope="row">Highest grade</th>
                <td class="infobox-data">
                    <a href="./Redpoint_(climbing)">Redpoint</a>: 5.14d
                </td>
            </tr>
        </table>
        """
        
        let items = InfoboxParser.extractMetadata(from: html)
        
        XCTAssertEqual(items.count, 1)
        
        // Expected Markdown. 
        // Note: Markdown link `[Text](Url)` breaks if Url has closing paren `)` unless escaped.
        // Standard markdown parser behavior: `[Redpoint](..._(climbing))` often terminates at first `)`.
        // Result: `[Redpoint](..._(climbing)` + `)` as text. 
        // OR `[Redpoint](..._(climbing)` is invalid.
        // Let's see what the parser produces string-wise first.
        
        let value = items.first?.value ?? ""
        // Note: The logic preserves ': 5.14d' which follows the link
        let expected = "[Redpoint](https://en.wikipedia.org/wiki/Redpoint_%28climbing%29): 5.14d"
        XCTAssertEqual(value, expected, "Markdown link conversion failed. Got: '\(value)'")
    }
    
    // Test 3: Tag End Finding Logic
    func testFindTagEndIndex() {
        // Simple
        let s1 = "class=\"foo\">Content"
        let i1 = InfoboxParser.findTagEndIndex(in: s1)
        let sub1 = s1[i1!...]
        XCTAssertEqual(sub1, "Content")
        
        // With quotes containing >
        let s2 = "data-val=\"foo > bar\">Content"
        let i2 = InfoboxParser.findTagEndIndex(in: s2)
        let sub2 = s2[i2!...]
        XCTAssertEqual(sub2, "Content")
        
        // With nested escaped quotes (JSON in attribute)
        // data-mw="{ &quot;key&quot;: &quot;val&quot; }"
        // The parser only sees \" if it's strictly a quote char.
        // HTML Attributes use &quot; inside double quotes usually.
        let s3 = "data-mw=\"{ &quot;foo&quot;: &quot;bar&quot; }\">Content"
        let i3 = InfoboxParser.findTagEndIndex(in: s3)
        let sub3 = s3[i3!...]
        XCTAssertEqual(sub3, "Content", "Failed to skip JSON with entities")
        
        // What if raw quotes?
        // data-mw='{"foo":"bar"}'
        let s4 = "data-mw='{\"foo\":\"bar\"}'>Content"
        let i4 = InfoboxParser.findTagEndIndex(in: s4)
        let sub4 = s4[i4!...]
        XCTAssertEqual(sub4, "Content", "Failed to skip single-quoted JSON")
        
        // With backslash escapes
        let s5 = "data-val=\"foo \\\" > bar\">Content"
        let i5 = InfoboxParser.findTagEndIndex(in: s5)
        let sub5 = s5[i5!...]
        XCTAssertEqual(sub5, "Content", "Failed to skip escaped quotes")
    }
    
    // Test 4: Formatting (Lists, Breaks)
    func testFormatting() {
        // Common Wikipedia Infobox patterns:
        // 1. Unordered lists for multiple values (e.g. Occupations)
        // 2. <br> tags for line breaks
        
        let html = """
        <table class="infobox">
            <tr>
                <th scope="row">Occupation</th>
                <td class="infobox-data">
                    <ul>
                        <li>Climber</li>
                        <li>Author</li>
                    </ul>
                </td>
            </tr>
            <tr>
                <th scope="row">Years active</th>
                <td class="infobox-data">2005–present<br />(climbing)</td>
            </tr>
        </table>
        """
        
        let items = InfoboxParser.extractMetadata(from: html)
        
        // Check Occupation (List)
        let occupation = items.first { $0.label == "Occupation" }?.value ?? ""
        // Expecting Markdown list
        XCTAssertTrue(occupation.contains("- Climber"), "Failed to parse list item 1. Got: \(occupation)")
        XCTAssertTrue(occupation.contains("- Author"), "Failed to parse list item 2")
        
        // Check Years Active (Break)
        let years = items.first { $0.label == "Years active" }?.value ?? ""
        // Expecting newline
        XCTAssertTrue(years.contains("\n"), "Failed to parse <br> tag. Got: \(years)")
    }
    
    // Test 5: Citation Removal
    func testCitationRemoval() {
        let html = """
        <table class="infobox">
            <tr>
                <th scope="row">Children</th>
                <td class="infobox-data">2<sup id="cite_ref-2" class="reference"><a href="#cite_note-2">[2]</a></sup></td>
            </tr>
        </table>
        """
        
        let items = InfoboxParser.extractMetadata(from: html)
        let children = items.first { $0.label == "Children" }?.value ?? ""
        XCTAssertEqual(children, "2", "Failed to remove citation. Got: \(children)")
    }
        
    // Test 6: Nested JSON Garbage (Reproduction)
    func testGarbageLeaking() {
        // The user sees: Sanni McCandless (married"}}">m. 2020)
        // This implies the parser sliced at a '>' inside the data-mw attribute.
        // Likely structure: data-mw="{... "foo": "bar" ...}" >
        
        // This specific string mimicking the failure:
        let html = """
        <table class="infobox">
            <tr>
                <th scope="row">Spouse</th>
                <td class="infobox-data" data-mw="{&quot;parts&quot;:[{&quot;template&quot;:{&quot;target&quot;:{&quot;wt&quot;:&quot;married&quot;,&quot;href&quot;:&quot;./Template:Married&quot;},&quot;params&quot;:{},&quot;i&quot;:0}}]}">Sanni McCandless (married)</td>
            </tr>
        </table>
        """
        
        let items = InfoboxParser.extractMetadata(from: html)
        let value = items.first?.value ?? ""
        
        XCTAssertFalse(value.contains("}}"), "Parser leaked JSON characters. Got: \(value)")
        XCTAssertEqual(value, "Sanni McCandless (married)")
    }

}
