${header}
namespace Boo.Lang.Compiler.Ast

import System

[Serializable]
public enum NodeType:
<%
for item in array(model.GetConcreteAstNodes()):
%>	${item.Name}
<%
end
%>
