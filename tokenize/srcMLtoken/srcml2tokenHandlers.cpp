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

void srcml2tokenHandlers::setPosition(const std::string newPos)
{
    pos = newPos;
    //std::cout << "setting position " << newPos << std::endl;
}

void srcml2tokenHandlers::setPosition(const Attributes& attrs)
{
    pos = position(attrs);
}

std::string srcml2tokenHandlers::position(const Attributes& attrs)
{
    std::string p = "";
    XMLCh* lineName= XMLString::transcode("pos:line");
    char* line = XMLString::transcode(attrs.getValue(lineName));
    XMLCh* colName= XMLString::transcode("pos:column");
    char* col = XMLString::transcode(attrs.getValue(colName));


    if (line != NULL && col != NULL) {
//        std::cout << "---"<< line << ":" << col << "---" << std::endl;
        p = line;
        p = p + ":" + col;
        free(line);
        free(col);
    }
//    std::cout << "calling position " << p << std::endl;

    return p;
}



std::string srcml2tokenHandlers::getPosition()
{
    return pos;
}



// ---------------------------------------------------------------------------
//  srcml2tokenHandlers: Implementation of the SAX DocumentHandler interface
// ---------------------------------------------------------------------------
void srcml2tokenHandlers::startElement(const XMLCh* const //uri
                                     , const XMLCh* const localname
                                     , const XMLCh* const qname
                                   , const Attributes& attrs)
{
    char *tagLocal = XMLString::transcode(localname);
//    char *tagName = XMLString::transcode(qname);
    std::string tmp = position(attrs);
    if (tmp != "")  {
        currentPos = tmp;
    }
    if (depth <= 1)  {
        setPosition(currentPos);
        //std::cout << "-" << "\t" << tagName << " " << depth << std::endl;
        std::cout << "-:-" << "\t" << "begin_" << tagLocal << std::endl;
    }

    if (currentContent.length() > 0 ) {
        std::cout << getPosition() << "\t" << currentContent << std::endl;
        currentContent = "";
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
        std::cout << getPosition() << "\t" << currentContent << std::endl;
        currentContent = "";
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
    std::string st = mytrim(XMLString::transcode(chars));
    std::string node = mystack.top();

    
    if (st.length() > 0) {
        std::replace( st.begin(), st.end(), '\n', ' ');

        if (currentContent.length() == 0) {
            setPosition(currentPos);
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
