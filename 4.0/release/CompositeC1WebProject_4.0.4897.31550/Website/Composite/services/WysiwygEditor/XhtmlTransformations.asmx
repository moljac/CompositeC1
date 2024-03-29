<%@ WebService Language="C#" Class="Composite.Services.XhtmlTransformations" %>

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Services;
using System.Web.Services.Protocols;
using System.Xml.Linq;
using Composite.Core.Extensions;
using Composite.Data.DynamicTypes;
using Composite.Functions;
using Composite.Core.Logging;
using Composite.Core.ResourceSystem;
using Composite.Core.WebClient;
using Composite.Core.WebClient.Services.WysiwygEditor;
using Composite.Core.Xml;
using Composite.Data;
using Composite.Core.Types;

namespace Composite.Services
{

    public class XhtmlTransformationResult
    {
        public string XhtmlFragment { get; set; }
        public string Warnings { get; set; }
    }


    public class FunctionInfo
    {
        public string FunctionMarkup { get; set; }
        public bool RequireConfiguration { get; set; }
    }



    [WebService(Namespace = "http://www.composite.net/ns/management")]
    [SoapDocumentService(RoutingStyle = SoapServiceRoutingStyle.RequestElement)]
    public class XhtmlTransformations : System.Web.Services.WebService
    {

        [WebMethod]
        public XhtmlTransformationResult TinyContentToStructuredContent(string htmlFragment)
        {
            try
            {
                string warnings = "";
                string xsltPath = Server.MapPath("..\\..\\transformations\\WysiwygEditor_TinyContentToStructuredContent.xsl");

                XDocument structuredResult;
                try
                {
                    Dictionary<string, string> xsltParameters = new Dictionary<string, string>();
                    xsltParameters.Add("requesthostname", HttpContext.Current.Request.Url.Host);
                    xsltParameters.Add("requestport", HttpContext.Current.Request.Url.Port.ToString());
                    xsltParameters.Add("requestscheme", HttpContext.Current.Request.Url.Scheme);
                    xsltParameters.Add("requestapppath", UrlUtils.PublicRootPath);

                    structuredResult = MarkupTransformationServices.RepairXhtmlAndTransform(WrapInnerBody(htmlFragment), xsltPath, xsltParameters, out warnings);
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException("Parse failed for \n" + htmlFragment, ex);
                }

                List<XElement> htmlWysiwygImages = structuredResult
                    .Descendants(Namespaces.Xhtml + "img")
                    .Where(e => e.Attribute("alt") != null 
                                && e.Attribute("class") != null
                                && e.Attribute("class").Value.Contains("compositeHtmlWysiwygRepresentation")).ToList();

                foreach (var htmlWysiwygImageElement in htmlWysiwygImages)
                {
                    try
                    {
                        string html = htmlWysiwygImageElement.Attribute("alt").Value;
                        XElement functionElement = XElement.Parse(html);

                        if (IsFunctionAloneInParagraph(htmlWysiwygImageElement))
                        {
                            htmlWysiwygImageElement.Parent.ReplaceWith(functionElement);
                        }
                        else
                        {
                            htmlWysiwygImageElement.ReplaceWith(functionElement);
                        }
                    }
                    catch (Exception ex)
                    {
                        htmlWysiwygImageElement.ReplaceWith(new XText("HTML PARSE FAILED: " + ex.Message));
                    }
                }



                List<XElement> functionImages =
                    structuredResult
                    .Descendants()
                    .Where(e => e.Name.LocalName == "img"
                            && e.Attribute("alt") != null
                           && e.Attribute("class") != null
                           && e.Attribute("class").Value.Contains("compositeFunctionWysiwygRepresentation")).ToList();
                
                foreach (var functionImageElement in functionImages)
                {
                    var nextNode = functionImageElement.NextNode;

                    // Removing "&#160;" symbols that may appear between function call images
                    if (nextNode != null
                        && nextNode.NextNode != null
                        && nextNode is XText
                        && nextNode.NextNode is XElement
                        && string.IsNullOrWhiteSpace((nextNode as XText).Value.Replace("&#160;", ""))
                        && functionImages.Contains(nextNode.NextNode as XElement))
                    {
                        nextNode.Remove();
                    }

                    // Replacing function call images with function markup
                    try
                    {
                        string functionMarkup = functionImageElement.Attribute("alt").Value;
                        XElement functionElement = XElement.Parse(functionMarkup);

                        if (IsFunctionAloneInParagraph(functionImageElement))
                        {
                            functionImageElement.Parent.ReplaceWith(functionElement);
                        }
                        else
                        {
                            functionImageElement.ReplaceWith(functionElement);
                        }
                    }
                    catch (Exception ex)
                    {
                        functionImageElement.ReplaceWith(new XText("FUNCTION MARKUP PARSE FAILED: " + ex.Message));
                    }
                }


                IEnumerable<XElement> dataFieldReferenceImages = 
                    structuredResult.Descendants(Namespaces.Xhtml + "img")
                    .Where(f => f.Attribute("class") != null 
                                && f.Attribute("class").Value.Contains("compositeFieldReferenceWysiwygRepresentation"));
                
                foreach (var referenceImageElement in dataFieldReferenceImages.ToList())
                {
                    try
                    {
                        string[] parts = HttpUtility.UrlDecode(referenceImageElement.Attribute("alt").Value).Split('\\');
                        string typeName = parts[0];
                        string fieldName = parts[1];

                        referenceImageElement.ReplaceWith(DynamicTypeMarkupServices.GetReferenceElement(fieldName, typeName));
                    }
                    catch (Exception ex)
                    {
                        referenceImageElement.ReplaceWith(new XText("FIELD REFERENCE MARKUP PARSE FAILED: " + ex.Message));
                    }
                }

                FixTinyMceMalEncodingOfInternationalUrlHostNames(structuredResult);

                string bodyInnerXhtml = MarkupTransformationServices.OutputBodyDescendants(structuredResult);

                return new XhtmlTransformationResult
                {
                    Warnings = warnings,
                    XhtmlFragment = FixXhtmlFragment(bodyInnerXhtml)
                };
            }
            catch (Exception ex)
            {
                LoggingService.LogError("XhtmlTransformation", ex.ToString());

                throw;
            }
        }

        private static readonly List<XName> paragraphList = new List<XName>(){
				Namespaces.Xhtml + "p",
				Namespaces.Xhtml + "h1",
				Namespaces.Xhtml + "h2",
				Namespaces.Xhtml + "h3",
				Namespaces.Xhtml + "h4",
				Namespaces.Xhtml + "h5",
				Namespaces.Xhtml + "h6"};

        private static bool IsFunctionAloneInParagraph(XElement element)
        {
            if (element.ElementsBeforeSelf().Any(d => d.Name != Namespaces.Xhtml + "br")
                || element.ElementsAfterSelf().Any(d => d.Name != Namespaces.Xhtml + "br")
                || !paragraphList.Contains(element.Parent.Name)
                || element.Parent.Value.Replace("&#160;", "").Trim() != string.Empty)
                return false;

            return true;
        }

        private static string FixXhtmlFragment(string xhtmlFragment)
        {
            xhtmlFragment = Regex.Replace(xhtmlFragment, @"(\s)\r\n</script>", "$1</script>", RegexOptions.Multiline);
            return xhtmlFragment.Replace("\xA0", "&#160;").Replace("&nbsp;", "&#160;");
        }

        // Fixing issue where tiny 
        private void FixTinyMceMalEncodingOfInternationalUrlHostNames(XDocument xhtmlDoc)
        {
            var urlAttributes = xhtmlDoc.Descendants().Attributes().Where(f => f.Value.StartsWith("http://") || f.Value.StartsWith("https://"));
            foreach (XAttribute urlAttribute in urlAttributes)
            {
                string url = urlAttribute.Value;
                string urlWithoutProtocol = url.Substring(url.IndexOf("//") + 2);
                string urlHostWithPort = (urlWithoutProtocol.Contains("/") ? urlWithoutProtocol.Substring(0, urlWithoutProtocol.IndexOf("/")) : urlWithoutProtocol);
                string urlHost = (urlHostWithPort.Contains(":") ? urlHostWithPort.Substring(0, urlHostWithPort.IndexOf(":")) : urlHostWithPort);
                if (urlHost != HttpUtility.UrlDecode(urlHost))
                {
                    urlAttribute.Value = urlAttribute.Value.Replace(urlHost, HttpUtility.UrlDecode(urlHost));
                }
            }
        }



        [WebMethod]
        public XhtmlTransformationResult StructuredContentToTinyContent(string htmlFragment)
        {
            try
            {
                string warnings = "";
                string XhtmlPassSsltPath = Server.MapPath("..\\..\\transformations\\WysiwygEditor_StructuredContentToTinyContent.xsl");

                string html = WrapInnerBody(htmlFragment);

                XDocument xml = XDocument.Parse(html);

                IEnumerable<XElement> functionRoots = xml
                    .Descendants(Namespaces.Function10 + "function")
                    .Where(f => f.Ancestors(Namespaces.Function10 + "function").Any() == false);

                foreach (var functionElement in functionRoots.ToList())
                {
                    functionElement.ReplaceWith(GetImageTagForFunctionCall(functionElement));
                }

                IEnumerable<XElement> dataFieldReferences = xml.Descendants(Namespaces.DynamicData10 + "fieldreference");
                foreach (var referenceElement in dataFieldReferences.ToList())
                {
                    referenceElement.ReplaceWith(GetImageTagForDynamicDataFieldReference(referenceElement));
                }

                var unHandledHtmlElementNames = new List<XName>
                                                    {
                                                        Namespaces.Xhtml + "audio",
                                                        Namespaces.Xhtml + "canvas",
                                                        Namespaces.Xhtml + "embed",
                                                        Namespaces.Xhtml + "iframe",
                                                        Namespaces.Xhtml + "map",
                                                        Namespaces.Xhtml + "object",
                                                        Namespaces.Xhtml + "script",
                                                        Namespaces.Xhtml + "noscript",
                                                        Namespaces.Xhtml + "video"
                                                    };

                IEnumerable<XElement> langElements = xml.Descendants().Where(f => f.Name.Namespace == Namespaces.Localization10);
                foreach (var langElement in langElements.ToList())
                {
                    langElement.ReplaceWith(GetImageTagForLangElement(langElement));
                }

                IEnumerable<XElement> unHandledHtmlElements = xml.Descendants().Where(f => f.Name.Namespace != Namespaces.Xhtml || unHandledHtmlElementNames.Contains(f.Name));
                foreach (var unHandledHtmlElement in unHandledHtmlElements.ToList())
                {
                    unHandledHtmlElement.ReplaceWith(GetImageTagForHtmlElement(unHandledHtmlElement));
                }

                Dictionary<string, string> xsltParameters = new Dictionary<string, string>();
                xsltParameters.Add("requestapppath", UrlUtils.PublicRootPath);

                XDocument structuredResult = MarkupTransformationServices.RepairXhtmlAndTransform(xml.ToString(), XhtmlPassSsltPath, xsltParameters, out warnings);

                string bodyInnerXhtml = MarkupTransformationServices.OutputBodyDescendants(structuredResult);

                return new XhtmlTransformationResult
                {
                    Warnings = warnings,
                    XhtmlFragment = FixXhtmlFragment(bodyInnerXhtml)
                };
            }
            catch (Exception ex)
            {
                LoggingService.LogError("XhtmlTransformation", ex.ToString());
                throw;
            }
        }

        [WebMethod]
        public string GetImageTagForFunctionCall(string functionMarkup)
        {
            XElement functionElement;

            try
            {
                functionElement = XElement.Parse(functionMarkup);
            }
            catch (Exception ex)
            {
                throw new ArgumentException("Unable to parse functionMarkup as XML", ex);
            }

            return GetImageTagForFunctionCall(functionElement).ToString(SaveOptions.DisableFormatting);
        }



        [WebMethod]
        public FunctionInfo GetFunctionInfo(string functionName)
        {
            IFunction function = FunctionFacade.GetFunction(functionName);

            FunctionRuntimeTreeNode functionRuntimeTreeNode = new FunctionRuntimeTreeNode(function);

            FunctionInfo functionInfo = new FunctionInfo();

            functionInfo.FunctionMarkup = functionRuntimeTreeNode.Serialize().ToString();
            functionInfo.RequireConfiguration = function.ParameterProfiles.Any();

            return functionInfo;
        }



        private XElement GetImageTagForDynamicDataFieldReference(XElement fieldReferenceElement)
        {
            string typeName = fieldReferenceElement.Attribute("typemanagername").Value;

            Type type = TypeManager.GetType(typeName);
            if (!typeof(IData).IsAssignableFrom(type))
            {
                string fieldName = fieldReferenceElement.Attribute("fieldname").Value;

                return GetImageTagForDynamicDataFieldReference(fieldName, fieldName, type.AssemblyQualifiedName, type.AssemblyQualifiedName);                
            }

            DataTypeDescriptor typeDescriptor;
            DataFieldDescriptor fieldDescriptor;

            if (!DynamicTypeMarkupServices.TryGetDescriptors(fieldReferenceElement, out typeDescriptor, out fieldDescriptor))
            {
                return null;
            }

            return GetImageTagForDynamicDataFieldReference(fieldDescriptor, typeDescriptor);
        }


        private XElement GetImageTagForHtmlElement(XElement element)
        {
            string description = element.ToString().Replace(" xmlns=\"http://www.w3.org/1999/xhtml\"", "");
            string title = "HTML block";

            var descriptionLines = description.Split('\n');
            if (descriptionLines.Count() > 6)
            {
                description = string.Format("{0}\n{1}\n{2}\n...\n{3}", descriptionLines[0], descriptionLines[1],
                                            descriptionLines[2], descriptionLines.Last());
            }

            string imageUrl = GetFunctionBoxImageUrl("html", title, description);

            return new XElement(Namespaces.Xhtml + "img",
                new XAttribute("src", imageUrl),
                new XAttribute("class", "compositeHtmlWysiwygRepresentation"),
                new XAttribute("alt", element.ToString())
                );
        }

        /*
                <lang:switch xmlns:lang="http://www.composite.net/ns/localization/1.0">
                    <lang:when culture="da-DK">DK<img src="/dk-logo.png" title="Dansk logo" /></lang:when>
                    <lang:when culture="en-US">EN<img src="/us-logo.png" title="American logo" /></lang:when>
                    <lang:default>No logo available</lang:default>
                </lang:switch>

        */
        private XElement GetImageTagForLangElement(XElement element)
        {
            XName switchName = Namespaces.Localization10 + "switch";
            XName stringName = Namespaces.Localization10 + "string";

            string title = "Language specific block";
            StringBuilder description = new StringBuilder();

            try
            {

                if (element.Name == stringName)
                {
                    description.AppendLine(element.Attribute("key").Value);
                }

                if (element.Name == switchName)
                {
                    foreach (var option in element.Elements().Where(e => e.Name.Namespace == Namespaces.Localization10))
                    {
                        int toGrab = Math.Min(35, option.Value.Length);
                        string elipsis = (option.Value.Length > 35 ? "..." : "");
                        string descriptionContent = string.Format("{0}{1}",
                                option.Value.Substring(0, toGrab),
                                elipsis);

                        if (String.IsNullOrWhiteSpace(option.Value) && option.Nodes().Any())
                        {
                            description.Append("(html code)");
                        }

                        switch (option.Name.LocalName)
                        {
                            case "when":
                                description.AppendFormat("{0}: {1}",
                                    option.Attribute("culture").Value,
                                    descriptionContent);
                                break;
                            case "default":
                                description.AppendLine();
                                description.AppendFormat("Default: {0}",
                                    descriptionContent);
                                break;
                            default:
                                break;
                        }
                        description.AppendLine("\n\n\n\n\n\n"); /* wtf - do I need this? */
                    }
                }
            }
            catch (Exception)
            {
                description.AppendLine("[ ERROR PARSING MARKUP ]");
            }

            string imageUrl = GetFunctionBoxImageUrl("html", title, description.ToString());

            return new XElement(Namespaces.Xhtml + "img",
                new XAttribute("src", imageUrl),
                new XAttribute("class", "compositeHtmlWysiwygRepresentation"),
                new XAttribute("alt", element.ToString())
                );
        }


        private static string GetFunctionBoxImageUrl(string type, string title, string description)
        {
            string imageUrl = "~/Renderers/FunctionBox?type={0}&title={1}&description={2}".FormatWith(
                HttpUtility.UrlEncodeUnicode(type),
                HttpUtility.UrlEncodeUnicode(title),
                UrlUtils.ZipContent(description.Trim())); // ZIPping description as it may contain xml tags f.e. <iframe />

            return UrlUtils.ResolvePublicUrl(imageUrl);
        }
        

        private XElement GetImageTagForDynamicDataFieldReference(DataFieldDescriptor dataField, DataTypeDescriptor dataTypeDescriptor)
        {
            string fieldLabel = dataField.Name;

            if (dataField.FormRenderingProfile != null && dataField.FormRenderingProfile.Label != null)
            {
                fieldLabel = StringResourceSystemFacade.ParseString(dataField.FormRenderingProfile.Label);
            }

            return GetImageTagForDynamicDataFieldReference(dataField.Name, fieldLabel, dataTypeDescriptor.Name, dataTypeDescriptor.TypeManagerTypeName);
        }

        private XElement GetImageTagForDynamicDataFieldReference(string fieldName, string fieldLabel, string typeName, string uiFriendlyTypeName)
        {
            string imageUrl = string.Format("services/WysiwygEditor/FieldImage.ashx?name={0}&groupname={1}",
                HttpUtility.UrlEncodeUnicode(fieldLabel),
                HttpUtility.UrlEncodeUnicode(typeName));

            return new XElement(Namespaces.Xhtml + "img",
                new XAttribute("src", Composite.Core.WebClient.UrlUtils.ResolveAdminUrl(imageUrl)),
                new XAttribute("class", "compositeFieldReferenceWysiwygRepresentation"),
                new XAttribute("alt", HttpUtility.UrlEncodeUnicode(string.Format("{0}\\{1}", uiFriendlyTypeName, fieldName)))
                );
        }



        private XElement GetImageTagForFunctionCall(XElement functionElement)
        {
            string title;
            StringBuilder description = new StringBuilder();
            string compactMarkup = functionElement.ToString(SaveOptions.DisableFormatting);

            bool error = false;

            try
            {
                FunctionRuntimeTreeNode functionNode = (FunctionRuntimeTreeNode)FunctionFacade.BuildTree(functionElement);
                string functionName = functionNode.GetCompositeName();
                title = MakeTitleFromName(functionName);
                
                // description.AppendLine("[{0}]".FormatWith(functionName));
                
                string functionDescription = functionNode.GetDescription();
                if (!functionDescription.IsNullOrEmpty())
                {
                    functionDescription = StringResourceSystemFacade.ParseString(functionDescription);
                    description.AppendLine(functionDescription);
                }

                var setParams = functionNode.GetSetParameters().ToList();
                if (setParams.Any()) description.Append("\n");

                IEnumerable<ParameterProfile> parameterProfiles = FunctionFacade.GetFunction(functionName).ParameterProfiles;

                foreach (var setParam in setParams.Take(10))
                {
                    AddParameterInformation(description, setParam, parameterProfiles);
                }
                
                if (setParams.Count > 10)
                {
                    description.AppendLine("....");
                }
            }
            catch (Exception ex)
            {
                // TODO: should be localized?
                title = "Invalid function call";
                description.AppendLine(ex.Message);
                error = true;
            }

            string functionBoxUrl = GetFunctionBoxImageUrl(error ? "warning" : "function", title, description.ToString());

            XElement imagetag = new XElement(Namespaces.Xhtml + "img"
                , new XAttribute("alt", compactMarkup)
                , new XAttribute("src", functionBoxUrl)
                , new XAttribute("class", "compositeFunctionWysiwygRepresentation")
                );

            return imagetag;
        }

        private void AddParameterInformation(StringBuilder description, BaseParameterRuntimeTreeNode parameter, IEnumerable<ParameterProfile> parameterProfiles)
        {
            if (parameter.ContainsNestedFunctions || parameter is FunctionParameterRuntimeTreeNode)
            {
                description.AppendLine("{0} = ....".FormatWith(parameter.Name));
                return;
            }

            try
            {
                string paramValue = parameter.GetValue().ToString();
                string paramLabel = parameter.Name;

                try
                {
                    ParameterProfile parameterProfile = parameterProfiles.FirstOrDefault(f => f.Name == parameter.Name);
                    if (parameterProfile != null)
                    {
                        paramLabel = parameterProfile.LabelLocalized;
                        if (typeof(IDataReference).IsAssignableFrom(parameterProfile.Type))
                        {
                            IDataReference dataReference = ValueTypeConverter.Convert(parameter.GetValue(), parameterProfile.Type) as IDataReference;
                            if (dataReference != null)
                            {
                                paramValue = dataReference.Data.GetLabel();
                            }
                        }
                        else
                        {
                            if (parameterProfile.Type == typeof(XhtmlDocument))
                            {
                                XhtmlDocument xhtmlDoc = parameter.GetValue<XhtmlDocument>();
                                if (xhtmlDoc.Body.Nodes().Any() && xhtmlDoc.Head.Nodes().Any())
                                {
                                    paramValue = "(Empty HTML)";
                                }
                                else
                                {
                                    string bodyText = xhtmlDoc.Body.Value.Trim();
                                    paramValue = (bodyText.Length > 0 ? string.Format("HTML: {0}", bodyText) : "(HTML)");
                                }
                            }
                        }
                    }
                }
                catch (Exception)
                {
                    // just fall back to listing param names and raw values...
                }

                if (!paramValue.IsNullOrEmpty() && paramValue.Length > 35)
                {
                    if (paramValue.IndexOf(' ') == -1)
                    {
                        paramValue = "...";
                    }
                    else
                    {
                        paramValue = paramValue.Substring(0, 35) + "...";
                    }
                }
                        
                description.AppendLine("{0} = {1}".FormatWith(paramLabel, paramValue));
            }
            catch (Exception)
            {
                description.AppendLine("{0} = ....".FormatWith(parameter.Name));
            }
        }

        private string WrapInnerBody(string innerBodyMarkup)
        {
            if (innerBodyMarkup.StartsWith("<html") && innerBodyMarkup.Contains(Namespaces.Xhtml.NamespaceName))
            {
                return innerBodyMarkup;
            }

            return string.Format("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>None</title></head><body>{0}</body></html>", innerBodyMarkup);
        }



        private string MakeTitleFromName(string name)
        {
            string[] nameParts = name.Split('.');
            string titleBase = nameParts[nameParts.Length - 1];

            StringBuilder sb = new StringBuilder(titleBase.Substring(0, 1).ToUpper());

            bool lastWasUpper = true;

            for (int i = 1; i < titleBase.Length; i++)
            {
                string letter = titleBase.Substring(i, 1);
                if (letter != letter.ToLowerInvariant())
                {
                    bool nextLetterIsLower = (i < titleBase.Length - 1) && (titleBase.Substring(i + 1, 1).ToLowerInvariant() == titleBase.Substring(i + 1, 1));

                    if (!lastWasUpper || nextLetterIsLower)
                    {
                        sb.Append(" ");
                    }
                    lastWasUpper = true;
                }
                else
                {
                    lastWasUpper = false;
                }
                sb.Append(letter);
            }

            return sb.ToString();
        }

    }


}