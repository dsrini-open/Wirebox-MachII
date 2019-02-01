<!---

    Mach-II - A framework for object oriented MVC web applications in CFML
    Copyright (C) 2003-2010 GreatBizTools, LLC

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    Linking this library statically or dynamically with other modules is
    making a combined work based on this library.  Thus, the terms and
    conditions of the GNU General Public License cover the whole
    combination.

    As a special exception, the copyright holders of this library give you
    permission to link this library with independent modules to produce an
    executable, regardless of the license terms of these independent
    modules, and to copy and distribute the resulting executable under
    terms of your choice, provided that you also meet, for each linked
    independent module, the terms and conditions of the license of that
    module.  An independent module is a module which is not derived from
    or based on this library.  If you modify this library, you may extend
    this exception to your version of the library, but you are not
    obligated to do so.  If you do not wish to do so, delete this
    exception statement from your version.

------------------------------------------------------------------------------------------
SEE LICENSE FILE
------------------------------------------------------------------------------------------

Notes:
A Mach-II property that provides easy Wirebox integration with Mach-II applications.

Usage: Please verify the additional XXXwireboxProperty.xml file

The [beanFactoryPropertyName] parameter value is the name of the Mach-II property name
that will hold a reference to the wirebox beanFactory. This parameter
defaults to "wirebox" if not defined.

The [resolveMachIIDependencies] parameter value indicates if the property to "automagically"
wire Mach-II listeners/filters/plugins/properties.  This parameter defaults to FALSE if not defined.
- TRUE (resolves all Mach-II dependencies)
- FALSE (does not resolve Mach-II dependencies)

The [parentBeanFactoryScope] parameter values defines which scope to pull in the wirebox injector.
This parameter defaults to 'application'

The [autowireAttributeName] parameter indicates the name of the attribute to introspect
for in cfcomponent tags when using the dynamic autowire method generation feature of the
wirebox Property.  Autowire method generation injection allows you to put a list of wirebox
bean names in the autowire attribute (which default to 'depends') in cfcomponent tag of your
listeners, filters, plugins and properties CFC in Mach-II. wirebox property will automatically
generate and dynamically inject getters/setters for the listed bean names into your target
cfc at runtime.  This does not modify the contents of the cfc file, but injects dynamically
while the cfc is in memory.  This feature allows you to stop having to type out getters/setters
for the service that you want wirebox to inject into your cfc.

Example:
<cfcomponent extends="MachII.framework.Listener" depends="someService">
	... additional code ...
</cfcomponent>

This will dynamically inject a getSomeService() and setSomeService() method into this listener.
--->
<cfcomponent
	name="WireboxProperty"
	extends="MachII.framework.Property"
	hint="A Mach-II application property for easy wirebox integration"
	output="false">

	<!---
	PROPERTIES
	--->
	<cfset variables.instance = StructNew() />

	<!---
	INITALIZATION / CONFIGURATION
	--->
	<cffunction name="configure" access="public" returntype="void" output="false"
		hint="I initialize this property during framework startup.">

		<!--- Default vars --->
		<cfset var bf = "" />
		<cfset var factoryKey = "" />
		<cfset var i = 0 />

		<!--- Get the Mach-II property manager (gets the a module's property manager if this is a module) --->
		<cfset var propertyManager = getPropertyManager() />

		<!--- Determine the location of the bean def xml file --->
		<cfset var serviceDefXmlLocation = "" />

		<!--- Get all properties to pass to bean factory
			Create a new struct instead of doing a direct assignment otherwise parent
			property managers will suddendly have properties from modules since
			structs are by passed by reference
		--->
		<cfset var defaultProperties = StructNew() />

		<!--- todo: Default attributes set via mach-ii params --->
		<cfset var defaultAttributes = StructNew() />

		<!--- Locating and storing bean factory (from properties/params) --->
		<cfset var parentBeanFactoryScope = getParameter("parentBeanFactoryScope", "application") />
		<cfset var localBeanFactoryKey = getParameter("beanFactoryPropertyName", "wirebox") />

		<!--- Set the autowire attribute name --->
		<cfset setAutowireAttributeName(getParameter("autowireAttributeName", "depends")) />

		<!--- Get the properties from the current property manager --->
		<cfset StructAppend(defaultProperties, propertyManager.getProperties()) />

		<!--- Append the parent's default properties if we have a parent --->
		<cfif IsObject(getAppManager().getParent())>
			<cfset StructAppend(defaultProperties, propertyManager.getParent().getProperties(), false) />
		</cfif>

		<!--- Evaluate any dynamic properties --->
		<cfloop collection="#defaultProperties#" item="i">
			<cfif IsSimpleValue(defaultProperties[i]) AND REFindNoCase("\${(.)*?}", defaultProperties[i])>
				<cfset defaultProperties[i] = Evaluate(Mid(defaultProperties[i], 3, Len(defaultProperties[i]) -3)) />
			</cfif>
		</cfloop>

		<!--- Place a temporary reference of the AppManager into the request scope for the UtilityConnector --->
		<cfset request._MachIIAppManager = getAppManager() />

		<!--- Put a bean factory reference into Mach-II property manager --->
		<cfset bf = Evaluate('#parentBeanFactoryScope#.#localBeanFactoryKey#')>

		<cfset setProperty("beanFactoryName", localBeanFactoryKey) />
		<cfset setProperty(localBeanFactoryKey, bf) />

		<!--- Figure out application/server key --->
		<cfset factoryKey = localBeanFactoryKey />

		<!--- Append the module the parent and child are using the same property name for the bean factory --->
		<cfif Len(getAppManager().getModuleName()) AND getAppManager().getParent().getPropertyManager().isPropertyDefined(localBeanFactoryKey)>
			<cfset factoryKey = factoryKey & "_" & getAppManager().getModuleName() />
		</cfif>

		<cfset resolveDependencies() />
	</cffunction>

	<cffunction name="deconfigure" access="public" returntype="void" output="false"
		hint="Deregisters wirebox.">

		<!--- Deregister as onPostObjectReload callback --->
		<cfset getAppManager().removeOnObjectReloadCallback(this) />
	</cffunction>

	<!---
	PUBLIC FUNCTIONS
	--->

	<cffunction name="resolveDependencies" access="public" returntype="void" output="false"
		hint="Resolves Mach-II dependencies.">

		<cfset var targetBase = StructNew() />
		<cfset var targetObj = 0 />
		<cfset var targetMetadata = "" />
		<cfset var autowireAttributeName = getAutowireAttributeName() />
		<cfset var i = 0 />

		<!--- Only resolve if dependency resolution is on --->
		<cfif getParameter("resolveMachIIDependencies", false)>
			<cfset targetBase.targets = ArrayNew(1) />

			<!--- Get listener/filter/plugin/property targets --->
			<cfset getListeners(targetBase) />
			<cfset getFilters(targetBase) />
			<cfset getPlugins(targetBase) />
			<cfset getConfigurableProperties(targetBase) />

			<cfloop from="1" to="#ArrayLen(targetBase.targets)#" index="i">
				<!--- Get this iteration target object for easy use --->
				<cfset targetObj =  targetBase.targets[i] />

				<!--- Get metadata --->
				<cfset targetMetadata = GetMetadata(targetObj) />

				<!--- Autowire by dynamic method generation --->
				<cfset autowireByDynamicMethodGeneration(targetObj, targetMetadata, autowireAttributeName) />

				<!--- Autowire by defined setters --->
				<cfset autowireByDefinedSetters(targetObj, targetMetadata) />
			</cfloop>
		</cfif>
	</cffunction>

	<cffunction name="resolveDependency" access="public" returntype="void" output="false"
		hint="Resolves Mach-II dependency by passed object.">
		<cfargument name="targetObject" type="any" required="true"
			hint="Target object to resolve dependency." />

		<!--- Look for autowirable collaborators for any setters --->
		<cfset var targetMetadata = GetMetadata(arguments.targetObject) />

		<!--- If target object is a command --->
		<cfif StructKeyExists(targetMetadata, "extends")
			AND targetMetadata.extends.name EQ "MachII.framework.Command">
			<!--- Autowire by value from bean id method --->
			<cfset autowireByBeanIdValue(arguments.targetObject, targetMetadata) />
		<cfelse>
			<!--- Only resolve if dependency resolution is on --->
			<cfif getParameter("resolveMachIIDependencies", false)>
				<!--- Autowire by dynamic method generation --->
				<cfset autowireByDynamicMethodGeneration(arguments.targetObject, targetMetadata, getAutowireAttributeName()) />

				<!--- Autowire by defined setters --->
				<cfset autowireByDefinedSetters(arguments.targetObject, targetMetadata) />
			</cfif>
		</cfif>
	</cffunction>

	<!---
	PROTECTED FUNCTIONS
	--->

	<cffunction name="autowireByBeanIdValue" access="private" returntype="void" output="false"
		hint="Autowires by the value from the bean id method.">
		<cfargument name="targetObj" type="any" required="true" />
		<cfargument name="targetObjMetadata" type="any" required="true" />

		<cfset var beanFactory = getProperty(getProperty("beanFactoryName")) />
		<cfset var beanName = arguments.targetObj.getBeanId() />

		<cftry>
			<cfinvoke component="#arguments.targetObj#" method="setBean">
				<cfinvokeargument name="bean" value="#beanFactory.getInstance(beanName)#" />
			</cfinvoke>
			<!--- Faster to fast fail and handle a missing bean exception than to check if the bean exists in the factory --->
			<cfcatch type="all">
				<cfthrow message="Cannot find bean named '#beanName#' to autowire by method injection in a '#ListLast(targetObjMetadata.extends.name, '.')#' of type '#targetObjMetadata.name#' in module '#getAppManager().getModuleName()#'."
					detail="Original Exception: #getUtils().buildMessageFromCfCatch(cfcatch)#" />
			</cfcatch>
		</cftry>
	</cffunction>

	<cffunction name="autowireByDynamicMethodGeneration" access="private" returntype="void" output="false"
		hint="Autowires by dynamic method generation.">
		<cfargument name="targetObj" type="any" required="true" />
		<cfargument name="targetObjMetadata" type="any" required="true" />
		<cfargument name="autowireAttributeName" type="string" required="true" />

		<cfset var beanFactory = getProperty(getProperty("beanFactoryName")) />
		<cfset var autowireBeanNames = "" />
		<cfset var beanName = "" />
		<cfset var targets = StructNew() />
		<cfset var autowireCfc = "" />
		<cfset var i = 0 />

		<!--- Autowire by concrete setters (dynamically injected setters do not show up in the metadata) --->
		<cfif StructKeyExists(arguments.targetObjMetadata, arguments.autowireAttributeName)>

			<!--- Get all of the bean names to autowire --->
			<cfset autowireBeanNames = ListToArray(getUtils().trimList(arguments.targetObjMetadata[arguments.autowireAttributeName])) />

			<!--- Generate and instantiate autowire component with the getter/setter methods --->
			<!--- Use the utility inject util.injetion.GetterSetterInjectionMethods for Mach-II 1.9.0 --->
			<cfset autowireCfc = CreateObject("component", "MachII.properties.ColdSpringProperty_InjectionMethods").init(autowireBeanNames) />

			<!--- Build all the targets --->
			<cftry>
				<cfloop from="1" to="#ArrayLen(autowireBeanNames)#" index="i">
					<cfset beanName = autowireBeanNames[i] />

					<!--- Add appropriate bean if the factory has a bean by that name --->
					<cfset targets[beanName] = beanFactory.getInstance(beanName) />
				</cfloop>
				<!--- Faster to fast fail and handle a missing bean exception than to check if the bean exists in the factory --->
				<cfcatch type="any">
					<cfthrow type="MachII.properties.WireboxProperty.NoBean"
						message="Cannot load bean named '#beanName#' to autowire by method injection in a '#ListLast(targetObjMetadata.extends.name, '.')#' of type '#targetObjMetadata.name#' in module '#getAppManager().getModuleName()#'."
						detail="Original Exception: #getUtils().buildMessageFromCfCatch(cfcatch)#" />
				</cfcatch>
			</cftry>

			<!--- Inject the _methodInject() so we can get the methods into the variables scope
				in addition to the this scope of the component --->
			<cfset arguments.targetObj["_injectMethods"] = autowireCfc["_injectMethods"] />

			<!--- Now inject everything into the target --->
			<cfset arguments.targetObj._injectMethods(autowireCfc, targets) />

			<!--- Delete the _methodInject() from the target --->
			<cfset StructDelete(arguments.targetObj, "_injectMethods") />
		</cfif>
	</cffunction>

	<cffunction name="autowireByDefinedSetters" access="private" returntype="void" output="false"
		hint="Autowires by defined setters.">
		<cfargument name="targetObj" type="any" required="true" />
		<cfargument name="targetObjMetadata" type="any" required="true" />

		<cfset var beanFactory = getProperty(getProperty("beanFactoryName")) />
		<cfset var functionMetadata = "" />
		<cfset var setterName = "" />
		<cfset var beanName = "" />
		<cfset var access = "" />
		<cfset var i = 0 />

		<!--- Autowire by concrete setters (dynamically injected setters do not show up in the metadata) --->
		<cfif StructKeyExists(arguments.targetObjMetadata, "functions")>
			<cfloop from="1" to="#ArrayLen(arguments.targetObjMetadata.functions)#" index="i">
				<cfset functionMetadata = arguments.targetObjMetadata.functions[i] />

				<!--- first get the access type --->
				<cfif StructKeyExists(functionMetadata, "access")>
					<cfset access = functionMetadata.access />
				<cfelse>
					<cfset access = "public" />
				</cfif>

				<!--- if this is a 'real' setter --->
				<cfif Left(functionMetadata.name, 3) EQ "set" AND Arraylen(functionMetadata.parameters) EQ 1 AND access NEQ "private">

					<!--- look for a bean in the factory of the params's type --->
					<cfset setterName = Mid(functionMetadata.name, 4, Len(functionMetadata.name) - 3) />

					<!--- Get bean by setter name and if not found then get by type --->
					<cfif beanFactory.containsInstance(setterName)>
						<cfset beanName = setterName />
					<cfelse>
						<cfset beanName = "" />
					</cfif>

					<!--- If we found a bean, put the bean by calling the target object's setter --->
					<cfif Len(beanName)>
						<cftry>
							<cfinvoke component="#arguments.targetObj#" method="set#setterName#">
								<cfinvokeargument name="#functionMetadata.parameters[1].name#" value="#beanFactory.getInstance(beanName)#" />
							</cfinvoke>
							<cfcatch type="any">
								<cfthrow type="MachII.properties.WireboxProperty.NoBean"
									message="Cannot load bean named '#beanName#' to autowire by method injection in a '#ListLast(targetObjMetadata.extends.name, '.')#' of type '#targetObjMetadata.name#' in module '#getAppManager().getModuleName()#'."
									detail="Original Exception: #getUtils().buildMessageFromCfCatch(cfcatch)#" />
							</cfcatch>
						</cftry>
					</cfif>
				</cfif>
			</cfloop>
		</cfif>
	</cffunction>

	<cffunction name="getListeners" access="private" returntype="void" output="false"
		hint="Gets the listener targets.">
		<cfargument name="targetBase" type="struct" required="true" />

		<cfset var listenerManager = getAppManager().getListenerManager() />
		<cfset var listenerNames = listenerManager.getListenerNames() />
		<cfset var i = 0 />

		<!--- Append each retrieved listener and its' invoker to the targets array (in struct) --->
		<cfloop from="1" to="#ArrayLen(listenerNames)#" index="i">
			<cfset ArrayAppend(arguments.targetBase.targets, listenerManager.getListener(listenerNames[i])) />
		</cfloop>
	</cffunction>

	<cffunction name="getFilters" access="private" returntype="void" output="false"
		hint="Get the filter targets.">
		<cfargument name="targetBase" type="struct" required="true" />

		<cfset var filterManager = getAppManager().getFilterManager() />
		<cfset var filterNames = filterManager.getFilterNames() />
		<cfset var i = 0 />

		<!--- Append each retrieved filter to the targets array (in struct) --->
		<cfloop from="1" to="#ArrayLen(filterNames)#" index="i">
			<cfset ArrayAppend(arguments.targetBase.targets, filterManager.getFilter(filterNames[i])) />
		</cfloop>
	</cffunction>

	<cffunction name="getPlugins" access="private" returntype="void" output="false"
		hint="Get the plugin targets.">
		<cfargument name="targetBase" type="struct" required="true" />

		<cfset var pluginManager = getAppManager().getPluginManager() />
		<cfset var pluginNames = pluginManager.getPluginNames() />
		<cfset var i = 0 />

		<!--- Append each retrieved plugin to the targets array (in struct) --->
		<cfloop from="1" to="#ArrayLen(pluginNames)#" index="i">
			<cfset ArrayAppend(arguments.targetBase.targets, pluginManager.getPlugin(pluginNames[i])) />
		</cfloop>
	</cffunction>

	<cffunction name="getConfigurableProperties" access="private" returntype="void" output="false"
		hint="Get the configurable property targets.">
		<cfargument name="targetBase" type="struct" required="true" />

		<cfset var propertyManager = getAppManager().getPropertyManager() />
		<cfset var configurablePropertyNames = propertyManager.getConfigurablePropertyNames() />
		<cfset var i = 0 />

		<!--- Append each retrieved configurable properties to the targets array (in struct) --->
		<cfloop from="1" to="#ArrayLen(configurablePropertyNames)#" index="i">
			<cfset ArrayAppend(arguments.targetBase.targets, propertyManager.getProperty(configurablePropertyNames[i])) />
		</cfloop>
	</cffunction>


	<!---
	ACCESSORS
	--->
	<cffunction name="setAutowireAttributeName" access="private" returntype="void" output="false">
		<cfargument name="autowireAttributeName" type="string" required="true" />
		<cfset variables.instance.autowireAttributeName = arguments.autowireAttributeName />
	</cffunction>
	<cffunction name="getAutowireAttributeName" access="public" returntype="string" output="false">
		<cfreturn variables.instance.autowireAttributeName />
	</cffunction>

</cfcomponent>