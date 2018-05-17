/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 * 
 *      http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


// ---------------------------------------------------------------------------
//  Includes
// ---------------------------------------------------------------------------
#include <string.h>
#include <iostream>
#include <stack>
#include <string>
#include <stdio.h>
#include <algorithm>

#include "srcml2token.hpp"
#include <xercesc/sax2/Attributes.hpp>
#include <xercesc/sax/SAXParseException.hpp>
#include <xercesc/sax/SAXException.hpp>

#include <map>
#include <vector>

std::vector<int> lineMarkers {0};
std::vector<int> lineNumbers {1};


std::string get_attribute_value(const Attributes& attrs, std::string name) {
    XMLCh* revName= XMLString::transcode(name.c_str());
    char* st = XMLString::transcode(attrs.getValue(revName));
    std::string result = "";
    if (st != NULL)
        result = st;
    return result;
}

std::string mytrim(const std::string& str,
                 const std::string& whitespace = " \t\n")
{
    std::size_t strBegin = str.find_first_not_of(whitespace);
//    std::cout << "---[" << str << "]" << strBegin << std::endl;

    if (strBegin == std::string::npos)
        return ""; // no content

    int  strEnd = str.find_last_not_of(whitespace);
    int  strRange = strEnd - strBegin + 1;

    return str.substr(strBegin, strRange);
}

std::string mytrimBegin(const std::string& str,
                 const std::string& whitespace = " \t\n")
{
    std::size_t strBegin = str.find_first_not_of(whitespace);
//    std::cout << "---[" << str << "]" << strBegin << std::endl;

    if (strBegin == std::string::npos)
        return ""; // no content


    return str.substr(strBegin);
}

std::pair<int,int> findRow(int position) {
    //it is most likely we will use the last ones
    // rather than any so search from the end
    assert(lineMarkers.size() > 0);
    unsigned int i = lineMarkers.size()-1;
    while (i >= 0 && lineMarkers[i]> position) {
        i--;
    }
    assert(i >=0 && i < lineMarkers.size());
    
    return {lineMarkers[i], lineNumbers[i]} ;
}


std::string srcml2tokenHandlers::newGetPosition() {
//    std::cout << "position [" << currentContentOriginal  << "]";

    auto st = mytrimBegin(currentContentOriginal);

//    int whitespace = currentContentOriginal.size() - st.size();
    int beginning = all_size - st.size();

    auto prevRow = findRow(beginning);

    //std::cout <<"prev row " << prevRow.first << ":" << prevRow.second  << std::endl;
    
/*
    return std::to_string(all_size - st.size()) + ":" +
        std::to_string(row) + ":" + std::to_string(col-1);
*/
    auto col = beginning + 1 -  prevRow.first;
    return std::to_string(prevRow.second) + ":" + std::to_string(col);
}

void srcml2tokenHandlers::advance(std::string st) {
    int i=1;

    for(auto c:st) {
        if (c == '\n') {
            row++;
            auto offset = all_size + i;
            lineMarkers.push_back(offset);
            lineNumbers.push_back(row);
            col = 1;
        } else {
            col++;
        }
        i++;
    }
    all_size += st.size();
}



// ---------------------------------------------------------------------------
//  srcml2tokenHandlers: Constructors and Destructor
// ---------------------------------------------------------------------------
srcml2tokenHandlers::srcml2tokenHandlers() :
  depth(0)
{
    ;
}

srcml2tokenHandlers::~srcml2tokenHandlers()
{
}



// ---------------------------------------------------------------------------
//  srcml2tokenHandlers: Implementation of the SAX DocumentHandler interface
// ---------------------------------------------------------------------------
void srcml2tokenHandlers::startElement(const XMLCh* const //uri
                                     , const XMLCh* const localname
                                     , const XMLCh* const qname
                                       , const Attributes& attrs)
{
    std::string tagLocal = XMLString::transcode(localname);
//    char *tagName = XMLString::transcode(qname);
//    std::string savePos = position(attrs);
    std::string savePos = newGetPosition();
    if (savePos != "")  {
        currentPos = savePos;
    }    

    if (depth <= 1)  {

        //std::cout << "-" << "\t" << tagName << " " << depth << std::endl;

        if (tagLocal == "unit") {

//<unit xmlns="http://www.srcML.org/srcML/src" xmlns:cpp="http://www.srcML.org/srcML/cpp" xmlns:pos="http://www.srcML.org/srcML/position" revision="0.9.5" language="C" filename="test-exec/count.cpp" pos:tabs="8"><cpp:include pos:line="1" pos:column="1">#<cpp:directive pos:line="1" pos:column="2">include<pos:position pos:line="1" pos:column="9"/></cpp:directive> <cpp:file pos:line="1" pos:column="10">&lt;iostream&gt;<pos:position pos:line="1" pos:column="23"/></cpp:file></cpp:include>

            auto revision = get_attribute_value(attrs, "revision");
            auto language = get_attribute_value(attrs, "language");
            if (revision != "" && language != "") {
                std::cout << "-:-" << "\t" << "begin_unit|" <<
                    "revision:" << revision << ";" <<
                    "language:" << language << ";" <<
                    "cregit-version:" << CREGIT_VERSION <<
                    std::endl;
            } else {
                std::cout << "-:-" << "\t" << "begin_" << tagLocal << std::endl;
            }
        } else {
            std::cout << "-:-" << "\t" << "begin_" << tagLocal << std::endl;
        }
    }

    if (currentContent.length() > 0 ) {
        // we output the content of the previous tag here...
        std::cout << newGetPosition() << "\t" << currentContent << std::endl;
        currentContent = "";
        currentContentOriginal = "";
    }
    
    
    mystack.push(tagLocal);
    toOutputStack.push(0);
    depth++;

//    XMLString::release(line);
    //XMLString::release(col);

}

void srcml2tokenHandlers::endElement (const XMLCh *const /*uri*/,
                                    const XMLCh *const localname,
                                    const XMLCh *const /*qname*/)
{
    char *tagName = XMLString::transcode(localname);

    // No escapes are legal here
    if (currentContent.length() > 0 ) {
        std::cout << newGetPosition() << "\t" << currentContent << std::endl;

        currentContent = "";
        currentContentOriginal = "";
    } 

    std::string parent = mystack.top();


    mystack.pop();
    toOutputStack.pop();
    depth--;
    if (depth <= 1) 
        std::cout << "-:-" << "\t" << "end_" << tagName << std::endl;

}


void srcml2tokenHandlers::characters(  const   XMLCh* const    chars 
								    , const XMLSize_t length)
{
    std::string original = XMLString::transcode(chars);
    std::string st = mytrim(original);
    std::string node = mystack.top();

//    std::cout << "ORIGInAL [" << original <<"]" << std::endl;
    advance(original);
    currentContentOriginal+= original;
    
    if (st.length() > 0) {
        std::replace( st.begin(), st.end(), '\n', ' ');

        if (currentContent.length() == 0) {
            currentContent = mystack.top() + "|";
        }
        currentContent = currentContent + st;
    }
}        
    

void srcml2tokenHandlers::ignorableWhitespace( const   XMLCh* const /* chars */
										    , const XMLSize_t length)
{

}

void srcml2tokenHandlers::startDocument()
{
}


// ---------------------------------------------------------------------------
//  srcml2tokenHandlers: Overrides of the SAX ErrorHandler interface
// ---------------------------------------------------------------------------
void srcml2tokenHandlers::error(const SAXParseException& e)
{
    XERCES_STD_QUALIFIER cerr << "\nError at file " << StrX(e.getSystemId())
		 << ", line " << e.getLineNumber()
		 << ", char " << e.getColumnNumber()
         << "\n  Message: " << StrX(e.getMessage()) << XERCES_STD_QUALIFIER endl;
}

void srcml2tokenHandlers::fatalError(const SAXParseException& e)
{
    XERCES_STD_QUALIFIER cerr << "\nFatal Error at file " << StrX(e.getSystemId())
		 << ", line " << e.getLineNumber()
		 << ", char " << e.getColumnNumber()
                 << "\n  Message: " << StrX(e.getMessage()) << XERCES_STD_QUALIFIER endl;
}

void srcml2tokenHandlers::warning(const SAXParseException& e)
{
    XERCES_STD_QUALIFIER cerr << "\nWarning at file " << StrX(e.getSystemId())
		 << ", line " << e.getLineNumber()
		 << ", char " << e.getColumnNumber()
         << "\n  Message: " << StrX(e.getMessage()) << XERCES_STD_QUALIFIER endl;
}

void srcml2tokenHandlers::resetErrors()
{

}
