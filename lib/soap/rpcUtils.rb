=begin
SOAP4R - RPC utility.
Copyright (C) 2000, 2001 NAKAMURA Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end

require 'soap/baseData'


module SOAP


class SOAPBody < SOAPStruct
  public

  def request
    rootNode
  end

  def response
    if !@isFault
      if void?
	nil
      else
	# Initial element is [retVal].
	rootNode[ 0 ]
      end
    else
      rootNode
    end
  end

  def void?
    rootNode.nil? # || rootNode.is_a?( SOAPNil )
  end

  def fault
    if @isFault
      @data[ 'fault' ]
    else
      nil
    end
  end

  def setFault( faultData )
    @isFault = true
    addMember( 'fault', faultData )
  end
end


module Marshallable
  @@typeName = nil
  @@typeNamespace = nil

  alias __instance_variables instance_variables
  def instance_variables
    if block_given?
      self.__instance_variables.each do |key|
	yield( key, eval( key ))
      end
    else
      self.__instance_variables
    end
  end
end


module RPCUtils
  RubyTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/1.6'
  RubyCustomTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/custom'

  ApacheSOAPTypeNamespace = 'http://xml.apache.org/xml-soap'


  ###
  ## RPC specific elements
  #
  class SOAPMethod < NSDBase
    include SOAPCompoundtype

    attr_reader :namespace
    attr_reader :name

    attr_reader :paramDef
    attr_accessor :paramNames
    attr_reader :paramTypes
    attr_reader :params
    attr_reader :soapAction

    attr_accessor :retName
    attr_accessor :retVal
  
    def initialize( namespace, name, paramDef = nil, soapAction = nil )
      super( self.type.to_s )
  
      @namespace = namespace
      @name = name
  
      @paramDef = paramDef
      @paramNames = []
      @paramTypes = {}
      @params = {}

      @soapAction = soapAction

      @retName = nil
      @retVal = nil
  
      setParamDef if @paramDef
    end
  
    def setParams( params )
      params.each do | param, data |
        @params[ param ] = data
      end
    end
  
    def encode( ns )
      attrs = []
      createNS( attrs, ns )
      if !retVal
	# Should it be typed?
	# attrs.push( datatypeAttr( ns ))

	elems = []
        @paramNames.each do | param |
	  unless @params[ param ].is_a?( SOAPVoid )
	    elems << @params[ param ].encode( ns.clone, param )
	  end
	end

        # Element.new( ns.name( @namespace, @name ), attrs, elems )
	Node.initializeWithChildren( ns.name( @namespace, @name ), attrs, elems )
      else
	# Should it be typed?
	# attrs.push( datatypeAttrResponse( ns ))

	elems = []
	unless retVal.is_a?( SOAPVoid )
	  elems << retVal.encode( ns.clone, 'return' )
	end
        # Element.new( ns.name( @namespace, responseTypeName() ), attrs, retElem )
        Node.initializeWithChildren( ns.name( @namespace, responseTypeName() ), attrs, elems )
      end
    end
  
  private

    def datatypeAttr( ns )
      Attr.new( ns.name( XSD::InstanceNamespace, 'type' ), ns.name( @namespace, @name ))
    end

    def datatypeAttrResponse( ns )
      Attr.new( ns.name( XSD::InstanceNamespace, 'type' ), ns.name( @namespace, responseTypeName() ))
    end

    def createNS( attrs, ns )
      unless ns.assigned?( @namespace )
	tag = ns.assign( @namespace )
	attrs.push( Attr.new( 'xmlns:' << tag, @namespace ))
      end
    end

    def setParamDef
      @paramDef.each do | pair |
        type, name = pair
        type.scan( /[^,\s]+/ ).each do | typeToken |
  	case typeToken
  	when 'in'
  	  @paramNames.push( name )
  	  @paramTypes[ name ] = 1
  	when 'out'
  	  @paramNames.push( name )
  	  @paramTypes[ name ] = 2
  	when 'retval'
  	  if ( @retName )
	    raise MethodDefinitionError.new( 'Duplicated retval' )
  	  end
  	  @retName = name
  	else
  	  raise MethodDefinitionError.new( 'Unknown type: ' << typeToken )
  	end
        end
      end
    end
  
    def responseTypeName
      @name + 'Response'
    end
  end


  class SOAPVoid < XSDBase
    include SOAPBasetype
    extend SOAPModuleUtils

  public
    def initialize()
      @namespace = RubyCustomTypeNamespace
      @name = nil
      @id = nil
      @parent = nil
    end
  end


  ###
  ## Convert parameter
  #
  # For type unknown object.
  class Object
    attr_accessor :typeName, :typeNamespace
  end


  def obj2soap( obj )
    case obj
    when SOAPBasetype, SOAPCompoundtype
      obj
    when NilClass
      SOAPNil.new
    when TrueClass, FalseClass
      SOAPBoolean.new( obj )
    when String
      SOAPString.new( obj )
    when Time, Date
      SOAPDateTime.new( obj )
    when Fixnum
      SOAPInt.new( obj )
    when Float
      SOAPFloat.new( obj )
    when Integer
      SOAPInteger.new( obj )
    when Array
      typeName = getTypeName( obj )
      typeNamespace = getNamespace( obj ) || RubyTypeNamespace
      unless typeName
	typeName = XSD::AnyTypeLiteral
	typeNamespace = XSD::Namespace
      end
      param = SOAPArray.new( typeName )
      param.typeNamespace = typeNamespace
      obj.each do | var |
	param.add( obj2soap( var ))
      end
      param
    when Hash
      param = SOAPStruct.new( "Map" )
      param.typeNamespace = ApacheSOAPTypeNamespace
      i = 1
      obj.each do | key, value |
	elem = SOAPStruct.new( "mapItem" )
	elem.add( "key", obj2soap( key ))
	elem.add( "value", obj2soap( value ))
	param.add( "item#{ i }", elem )
	i += 1
      end
      param
    when Struct
      param = SOAPStruct.new( obj.type.to_s )
      param.typeNamespace = getNamespace( obj ) || RubyTypeNamespace
      obj.members.each do |member|
	param.add( member, obj2soap( obj[ member ] ))
      end
      param
    when SOAP::RPCUtils::Object
      typeName = obj.typeName
      param = SOAPStruct.new( typeName  )
      param.typeNamespace = obj.typeNamespace
      obj.instance_variables do |var, data|
	name = var.dup.sub!( /^@/, '' )
	param.add( name, obj2soap( data ))
      end
      param
    else
      typeName = getTypeName( obj ) || obj.type.to_s
      param = SOAPStruct.new( typeName  )
      param.typeNamespace = getNamespace( obj ) || RubyCustomTypeNamespace
      if obj.type.ancestors.member?( Marshallable )
	obj.instance_variables do |var, data|
	  name = var.dup.sub!( /^@/, '' )
	  param.add( name, obj2soap( data ))
	end
      else
        obj.instance_variables.each do |var|
	  name = var.dup.sub!( /^@/, '' )
	  param.add( name, obj2soap( obj.instance_eval( var )))
        end
      end
      param
    end
  end


  def soap2obj( node )
    case node
    when SOAPReference
      # ToDo: multi-reference decoding...
      soap2obj( node.__getobj__ )
    when SOAPNil
      nil
    when SOAPBase64
      # Stringify
      node.toString
    when SOAPArray
      obj = node.collect { |elem|
	soap2obj( elem )
      }
      obj.instance_eval( "@typeName = '#{ node.typeName }'; @typeNamespace = '#{ node.typeNamespace }'" )
      obj
    when SOAPStruct
      if node.typeEqual( RubyTypeNamespace, 'Hash' )
	obj = Hash.new
	keyArray = soap2obj( node.key )
	valueArray = soap2obj( node.value )
	while !keyArray.empty?
	  obj[ keyArray.shift ] = valueArray.shift
	end
	obj
      elsif node.typeEqual( ApacheSOAPTypeNamespace, 'Map' )
	obj = Hash.new
	node.each do | key, value |
	  obj[ soap2obj( value.key ) ] = soap2obj( value.value )
	end
	obj
      elsif node.typeEqual( XSD::Namespace, XSD::AnyTypeLiteral )
	unknownObj( node )
      else
	struct2obj( node )
      end
    when XSDBase
      node.data
    else
      node
    end
  end

private

  def getTypeName( obj )
    ret = nil
    begin
      ret = obj.instance_eval( "@typeName" ) || obj.instance_eval( "@@typeName" )
    rescue NameError
    end
    ret
  end

  def getNamespace( obj )
    ret = nil
    begin
      ret = obj.instance_eval( "@typeNamespace" ) || obj.instance_eval( "@@typeNamespace" )
    rescue NameError
    end
    ret
  end

  def unknownObj( node )
    klass = Object	# SOAP::RPCUtils::Object
    Thread.critical = true
    addWriter( klass, node )
    obj = klass.new
    node.each do |name, value|
      obj.send( name + "=", soap2obj( value ))
    end
    restoreWriter( klass, node )
    Thread.critical = false
    obj.typeNamespace = node.typeNamespace
    obj.typeName = node.typeName
    obj
  end

  def struct2obj( node )
    obj = nil
    typeName = node.typeName || node.instance_eval( "@name" )
    begin
      klass = Object.const_get( toTypeName( typeName ))
      if getNamespace( klass ) != node.typeNamespace
	raise NameError.new()
      elsif getTypeName( klass ) and ( getTypeName( klass ) != typeName )
	raise NameError.new()
      end

      Thread.critical = true
      addWriter( klass, node )
      obj = createEmptyObject( klass )
      node.each do |name, value|
	obj.send( name + "=", soap2obj( value ))
      end
      restoreWriter( klass, node )
      Thread.critical = false

    rescue NameError
      klass = nil
      structName = toTypeName( typeName )
      if ( Struct.constants - Struct.superclass.constants ).member?( structName )
	klass = Struct.const_get( structName )
	if klass.members.length != node.members.length
	  klass = Struct.new( structName, *node.members )
	end
      else
        klass = Struct.new( structName, *node.members )
      end
      arg = node.collect { |name, value| soap2obj( value ) }
      obj = klass.new( *arg )
    end

    obj
  end

  def createEmptyObject( klass )
    klass.module_eval <<EOS
      begin
	alias __initialize initialize
      rescue NameError
      end
      def initialize; end
EOS

    obj = klass.new

    klass.module_eval <<EOS
      undef initialize
      begin
	alias initialize __initialize
      rescue NameError
      end
EOS
    obj
  end

  def addWriter( klass, values )
    values.each do |name, value|
      klass.module_eval <<EOS
	begin
	  alias __#{ name }= #{ name }=
	rescue NameError
	end
	def #{ name }=( var )
	  @#{ name } = var
	end
EOS
    end
  end

  def restoreWriter( klass, values )
    values.each do |name, value|
      klass.module_eval <<EOS
	undef #{ name }=
	begin
	  alias #{ name }= __#{ name }=
	rescue NameError
	end
EOS
    end
  end

  def setInstanceVar( obj, var )
    obj.instance_eval( "alias __initialize initialize; def initialize; end" )
    obj.instance_eval( "undef initialize; alias initialize __initialize" )
    obj
  end

  def toTypeName( name )
    capitalize( name )
  end

  def capitalize( target )
    target.gsub('^([a-z])') { $1.tr!('[a-z]', '[A-Z]') }
  end
end


end
