//
//  generator.swift
//  fit
//
//  Created by Archer on 2018/10/24.
//  Copyright © 2018年 Archer. All rights reserved.
//

import Foundation

// MARK: GeneratorType
protocol GeneratorType {
    func generateFile() throws
}


// MARK: Context
class Context {
    
    let fate: Fate?
    let generator: GeneratorType?
    
    init(_ fate: Fate?) {
        self.fate = fate
        guard let config = fate?.config,
            let jsonString = fate?.jsonString else {
            generator = nil
            return
        }
        if config.outputFileType == .Swift {
            generator = SwiftFileGenerator(config, jsonString)
        } else {
            generator = ObjectiveCFileGenerator(config, jsonString)
        }
    }
    
    func generate() throws {
        try generator?.generateFile()
    }
}


// MARK: SwiftFileGenerator
class SwiftFileGenerator {
    
    let jsonString: String
    let config: Configration
    
    private var outputFileContent = ""
    private var tabStack = Stack<String>()
    private var bracketStack = Stack<String>()
    
    init(_ config: Configration, _ jsonString: String) {
        self.config = config
        self.jsonString = jsonString
    }
}

extension SwiftFileGenerator: GeneratorType {
    func generateFile() throws {
        let json = JSON(parseJSON: jsonString)
        if json.type == .dictionary {
            outputFileContent += """
            //
            //  \(config.outputFileName).swift
            //
            //  This file is auto generated by fit.
            //  Github: https://github.com/k
            //
            //  Copyright © 2018-present Archer. All rights reserved.
            //
            
            import Foundation \n\n
            """
            
            if config.frameworkType == .YYModel {
                if config.confirmsProtocol == .yes {
                    outputFileContent +=  """
                    @objcMembers
                    class \(config.outputFileName): NSObject, YYModel {\n\n
                    """
                } else {
                    outputFileContent +=  """
                    @objcMembers
                    class \(config.outputFileName): NSObject {\n\n
                    """
                }
            } else if config.frameworkType == .MJExtension {
                outputFileContent +=  """
                @objcMembers
                class \(config.outputFileName): NSObject {\n\n
                """
            } else {
                outputFileContent +=  """
                class \(config.outputFileName) {\n\n
                """
            }
            
            tabStack.push("\t")
            let jsonValue = json.dictionaryValue
            if config.useInnerClass == .yes {
                try generate(from: jsonValue)
            } else {
                try generate_v2(from: jsonValue)
            }
            try writeToFile()

        } else {
            throw GenerationError.jsonStringNotValid(jsonString: jsonString)
        }
    }
    
    private func generate(from dictionaryValue: [String : JSON]) throws {
        var tabs = tabStack.joined()
        var allGenericTypes = [String: String]()
        for (key, value) in dictionaryValue {
            switch value.type {
                case .number:
                    if strcmp(value.numberValue.objCType, NSIntEncodingType) == 0 {
                        outputFileContent += "\(tabs)var \(key): Int = 0\n"
                    } else { // hold every number type
                        outputFileContent += "\(tabs)var \(key): Double = 0\n"
                    }
                
                case .string:
                    outputFileContent += "\(tabs)var \(key): String?\n"
                
                case .bool:
                    outputFileContent += "\(tabs)var \(key): Bool = false\n"
                
                case .array:
                    if value.arrayValue.isEmpty { return }
                    bracketStack.push("[")
                    let jsonValue = value.arrayValue.first!
                    try generate(key: key, tabs: tabs, jsonValue: jsonValue, genericTypes: &allGenericTypes)
                
                case .dictionary:
                    let prefix = (key as NSString).substring(to: 1).uppercased()
                    let suffix = (key as NSString).substring(from: 1)
                    let genericType: String
                    if config.ignorePrefix == .yes {
                        genericType = "\(prefix + suffix)" + config.suffix
                    } else {
                        genericType = config.prefix + "\(prefix + suffix)" + config.suffix
                    }
                    outputFileContent += "\(tabs)var \(key): \(genericType)?\n\n"
                    
                    if config.frameworkType == .YYModel {
                        if config.confirmsProtocol == .yes {
                            outputFileContent +=  """
                            \(tabs)@objcMembers
                            \(tabs)class \(genericType): NSObject, YYModel {\n
                            """
                        } else {
                            outputFileContent +=  """
                            \(tabs)@objcMembers
                            \(tabs)class \(genericType): NSObject {\n
                            """
                        }
                    } else if config.frameworkType == .MJExtension {
                        outputFileContent +=  """
                        \(tabs)@objcMembers
                        \(tabs)class \(genericType): NSObject {\n
                        """
                    } else {
                        outputFileContent +=  """
                        \(tabs)class \(genericType) {\n
                        """
                    }
                
                    tabStack.push("\t")
                    try generate(from: value.dictionaryValue)
                
                case .null, .unknown: break
            }
        }
        
        if !allGenericTypes.isEmpty {
            var generics = ""
            let retracts = tabs.appending("\t\t\t")
            for (key, value) in allGenericTypes {
                generics += "\"\(key)\" : \(value).self,\n\(retracts)"
            }
            generics.removeLast(retracts.count + 2)
            if config.frameworkType == .YYModel {
                outputFileContent += """
                
                \(tabs)static func modelContainerPropertyGenericClass() -> [String : Any]? {
                    \(tabs)return [\(generics)]
                \(tabs)}\n
                """
            } else if config.frameworkType == .MJExtension {
                outputFileContent += """
                
                \(tabs)override static func mj_objectClassInArray() -> [AnyHashable : Any]! {
                    \(tabs)return [\(generics)]
                \(tabs)}\n
                """
            } else {
                // nothing goes here
            }
        }
        
        tabs.removeLast()
        outputFileContent += """
        \(tabs)}\n\n
        """
        
        tabStack.pop()
    }
    
    private func generate(key: String, tabs: String, jsonValue: JSON, genericTypes: inout [String: String]) throws {
        let lbrackets = bracketStack.joined()
        let rbrackets = lbrackets.map { _ in "]" }.joined()
        switch jsonValue.type {
            case .number:
                if strcmp(jsonValue.numberValue.objCType, NSIntEncodingType) == 0 {
                    outputFileContent += "\(tabs)var \(key): \(lbrackets)Int\(rbrackets)?\n"
                } else { // hold every number type
                    outputFileContent += "\(tabs)var \(key): \(lbrackets)Double\(rbrackets)?\n"
                }
            
            case .string:
                outputFileContent += "\(tabs)var \(key): \(lbrackets)String\(rbrackets)?\n"
            
            case .bool:
                outputFileContent += "\(tabs)var \(key): \(lbrackets)Bool\(rbrackets)?\n"
            
            case .array:
                if jsonValue.arrayValue.isEmpty { return }
                bracketStack.push("[")
                let value = jsonValue.arrayValue.first!
                try generate(key: key, tabs: tabs, jsonValue: value, genericTypes: &genericTypes)
            
            case .dictionary:
                let prefix = (key as NSString).substring(to: 1).uppercased()
                let suffix = (key as NSString).substring(from: 1)
                let genericType: String
                if config.ignorePrefix == .yes {
                    genericType = "\(prefix + suffix)" + config.suffix
                } else {
                    genericType = config.prefix + "\(prefix + suffix)" + config.suffix
                }
                genericTypes[key] = genericType
                
                outputFileContent += "\(tabs)var \(key): \(lbrackets)\(genericType)\(rbrackets)?\n\n"
                
                if config.frameworkType == .YYModel {
                    if config.confirmsProtocol == .yes {
                        outputFileContent +=  """
                        \(tabs)@objcMembers
                        \(tabs)class \(genericType): NSObject, YYModel {\n
                        """
                    } else {
                        outputFileContent +=  """
                        \(tabs)@objcMembers
                        \(tabs)class \(genericType): NSObject {\n
                        """
                    }
                } else if config.frameworkType == .MJExtension {
                    outputFileContent +=  """
                    \(tabs)@objcMembers
                    \(tabs)class \(genericType): NSObject {\n
                    """
                } else {
                    outputFileContent +=  """
                    \(tabs)class \(genericType) {\n
                    """
                }
                
                tabStack.push("\t")
                try generate(from: jsonValue.dictionaryValue)
            
            case .null, .unknown: break
        }
        bracketStack.pop()
    }
    
    private func generate_v2(from dictionaryValue: [String : JSON]) throws {
        var tabs = tabStack.joined()
        var allGenericTypes = [String: String]()
        var classKeyPairs = [String : [String : JSON]]()
        for (key, value) in dictionaryValue {
            switch value.type {
            case .number:
                if strcmp(value.numberValue.objCType, NSIntEncodingType) == 0 {
                    outputFileContent += "\(tabs)var \(key): Int = 0\n"
                } else { // hold every number type
                    outputFileContent += "\(tabs)var \(key): Double = 0\n"
                }
                
            case .string:
                outputFileContent += "\(tabs)var \(key): String?\n"
                
            case .bool:
                outputFileContent += "\(tabs)var \(key): Bool = false\n"
                
            case .array:
                if value.arrayValue.isEmpty { return }
                bracketStack.push("[")
                let jsonValue = value.arrayValue.first!
                try generate_v2(key: key, tabs: tabs, jsonValue: jsonValue, genericTypes: &allGenericTypes, classKeyPairs: &classKeyPairs)
                
            case .dictionary:
                let prefix = (key as NSString).substring(to: 1).uppercased()
                let suffix = (key as NSString).substring(from: 1)
                let genericType = config.prefix + "\(prefix + suffix)" + config.suffix

                classKeyPairs[genericType] = value.dictionaryValue
                outputFileContent += "\(tabs)var \(key): \(genericType)?\n"
                
            case .null, .unknown: break
            }
        }
        
        if !allGenericTypes.isEmpty {
            var generics = ""
            let retracts = tabs.appending("\t\t\t")
            for (key, value) in allGenericTypes {
                generics += "\"\(key)\" : \(value).self,\n\(retracts)"
            }
            generics.removeLast(retracts.count + 2)
            if config.frameworkType == .YYModel {
                outputFileContent += """
                
                \(tabs)static func modelContainerPropertyGenericClass() -> [String : Any]? {
                    \(tabs)return [\(generics)]
                \(tabs)}\n
                """
            } else if config.frameworkType == .MJExtension {
                outputFileContent += """
                
                \(tabs)override static func mj_objectClassInArray() -> [AnyHashable : Any]! {
                    \(tabs)return [\(generics)]
                \(tabs)}\n
                """
            } else {
                // nothing goes here
            }
        }
        
        tabs.removeLast()
        outputFileContent += """
        \(tabs)}\n\n
        """
        
        tabStack.pop()

        for (className, keyPairs) in classKeyPairs {
            if config.frameworkType == .YYModel {
                if config.confirmsProtocol == .yes {
                    outputFileContent +=  """
                    \(tabs)@objcMembers
                    \(tabs)class \(className): NSObject, YYModel {\n
                    """
                } else {
                    outputFileContent +=  """
                    \(tabs)@objcMembers
                    \(tabs)class \(className): NSObject {\n
                    """
                }
            } else if config.frameworkType == .MJExtension {
                outputFileContent +=  """
                \(tabs)@objcMembers
                \(tabs)class \(className): NSObject {\n
                """
            } else {
                outputFileContent +=  """
                \(tabs)class \(className) {\n
                """
            }
            
            tabStack.push("\t")
            try generate_v2(from: keyPairs)
        }
    }
    
    private func generate_v2(key: String, tabs: String, jsonValue: JSON, genericTypes: inout [String: String], classKeyPairs: inout [String : [String : JSON]]) throws {
        let lbrackets = bracketStack.joined()
        let rbrackets = lbrackets.map { _ in "]" }.joined()
        switch jsonValue.type {
        case .number:
            if strcmp(jsonValue.numberValue.objCType, NSIntEncodingType) == 0 {
                outputFileContent += "\(tabs)var \(key): \(lbrackets)Int\(rbrackets)?\n"
            } else { // hold every number type
                outputFileContent += "\(tabs)var \(key): \(lbrackets)Double\(rbrackets)?\n"
            }
            
        case .string:
            outputFileContent += "\(tabs)var \(key): \(lbrackets)String\(rbrackets)?\n"
            
        case .bool:
            outputFileContent += "\(tabs)var \(key): \(lbrackets)Bool\(rbrackets)?\n"
            
        case .array:
            if jsonValue.arrayValue.isEmpty { return }
            bracketStack.push("[")
            let value = jsonValue.arrayValue.first!
            try generate_v2(key: key, tabs: tabs, jsonValue: value, genericTypes: &genericTypes, classKeyPairs: &classKeyPairs)
            
        case .dictionary:
            let prefix = (key as NSString).substring(to: 1).uppercased()
            let suffix = (key as NSString).substring(from: 1)
            let genericType = config.prefix + "\(prefix + suffix)" + config.suffix
            
            genericTypes[key] = genericType
            classKeyPairs[genericType] = jsonValue.dictionaryValue
            outputFileContent += "\(tabs)var \(key): \(lbrackets)\(genericType)\(rbrackets)?\n"
            
        case .null, .unknown: break
        }
        bracketStack.pop()
    }
    
    private func writeToFile() throws {
        let filepath = try NSFileWritingDirectory()
        let filename = "/" + config.outputFileName + ".swift"
        try outputFileContent.write(toFile: filepath + filename, atomically: true, encoding: .utf8)
    }
}


// MARK: ObjectiveCFileGenerator
class ObjectiveCFileGenerator {
    
    let jsonString: String
    let config: Configration
    
    private var outputHeaderStack = Stack<String>()
    private var outputImplementationStack = Stack<String>()

    private var bracketStack = Stack<String>()
    
    init(_ config: Configration, _ jsonString: String) {
        self.config = config
        self.jsonString = jsonString
    }
}

extension ObjectiveCFileGenerator: GeneratorType {
    func generateFile() throws {
        let json = JSON(parseJSON: jsonString)
        if json.type == .dictionary {
            outputHeaderStack.push("NS_ASSUME_NONNULL_END")
            
            if config.frameworkType == .YYModel {
                if config.confirmsProtocol == .yes {
                    outputHeaderStack.push("""
                    @interface \(config.outputFileName) : NSObject<YYModel> \n
                    """)
                } else {
                    outputHeaderStack.push( """
                    @interface \(config.outputFileName) : NSObject \n
                    """)
                }
            } else if config.frameworkType == .MJExtension {
                outputHeaderStack.push("""
                @interface \(config.outputFileName) : NSObject \n
                """)
            } else {
                outputHeaderStack.push("""
                    @interface \(config.outputFileName) : NSObject \n
                    """)
            }
            
            outputImplementationStack.push("""
            @implementation \(config.outputFileName)\n
            """)
            
            let jsonValue = json.dictionaryValue
            try generate(from: jsonValue)
            try writeToFile()
        } else {
            throw GenerationError.jsonStringNotValid(jsonString: jsonString)
        }
    }
    
    private func generate(from dictionaryValue: [String : JSON]) throws {
        var allGenericTypes = [String: String]()
        var classKeyPairs = [String : [String : JSON]]()
        for (key, value) in dictionaryValue {
            switch value.type {
            case .number:
                if strcmp(value.numberValue.objCType, NSIntEncodingType) == 0 {
                    outputHeaderStack += "@property (nonatomic, assign) NSInteger \(key);\n"
                } else { // hold every number type
                    outputHeaderStack += "@property (nonatomic, assign) CGFloat \(key);\n"
                }
                
            case .string:
                outputHeaderStack += "@property (nonatomic, copy) NSString *\(key);\n"
                
            case .bool:
                outputHeaderStack += "@property (nonatomic, assign) BOOL \(key);\n"
                
            case .array:
                if value.arrayValue.isEmpty { return }
                bracketStack.push("[")
                let jsonValue = value.arrayValue.first!
                try generate(key: key, jsonValue: jsonValue, genericTypes: &allGenericTypes, classKeyPairs: &classKeyPairs)
                
            case .dictionary:
                let prefix = (key as NSString).substring(to: 1).uppercased()
                let suffix = (key as NSString).substring(from: 1)
                let genericType = config.prefix + "\(prefix + suffix)" + config.suffix
                
                classKeyPairs[genericType] = value.dictionaryValue
                outputHeaderStack += "@property (nonatomic, strong) \(genericType) *\(key);\n"
                
            case .null, .unknown: break
            }
        }
        
        if !allGenericTypes.isEmpty {
            var generics = ""
            let retracts = "\t\t\t "
            for (key, value) in allGenericTypes {
                generics += "@\"\(key)\" : \(value).class,\n\(retracts)"
            }
            generics.removeLast(retracts.count + 2)
            if config.frameworkType == .YYModel {
                outputImplementationStack += """
                + (NSDictionary<NSString *,id> *)modelContainerPropertyGenericClass {
                    return @{\(generics)};
                }\n
                """
            } else if config.frameworkType == .MJExtension {
                outputImplementationStack += """
                + (NSDictionary *)mj_objectClassInArray { {
                    return @{\(generics)};
                }\n
                """
            } else {
                // nothing goes here
            }
        }
        
        outputHeaderStack += "@end\n\n"
        outputImplementationStack += "@end\n\n"
        
        for (className, keyPairs) in classKeyPairs {
            if config.frameworkType == .YYModel &&
                config.confirmsProtocol == .yes {
                outputHeaderStack.push("""
                    @interface \(className) : NSObject<YYModel> \n
                    """)
            } else {
                outputHeaderStack.push("""
                    @interface \(className) : NSObject \n
                    """)
            }
            outputImplementationStack.push("""
                @implementation \(className)\n
                """)
            
            try generate(from: keyPairs)
        }
    }
    
    private func generate(key: String, jsonValue: JSON, genericTypes: inout [String: String], classKeyPairs: inout [String : [String : JSON]]) throws {
        switch jsonValue.type {
        case .number, .bool:
            outputHeaderStack += "@property (nonatomic, strong) NSArray<NSNumber *> *\(key);\n"

        case .string:
            outputHeaderStack += "@property (nonatomic, strong) NSArray<NSString *> *\(key);\n"

        case .array:
            debugPrint("-fit: two-dimensional arrays are not supported yet")

        case .dictionary:
            let prefix = (key as NSString).substring(to: 1).uppercased()
            let suffix = (key as NSString).substring(from: 1)
            let genericType = config.prefix + "\(prefix + suffix)" + config.suffix

            genericTypes[key] = genericType
            classKeyPairs[genericType] = jsonValue.dictionaryValue
            outputHeaderStack += "@property (nonatomic, strong) NSArray<\(genericType) *> *\(key);\n"

        case .null, .unknown: break
        }
    }
    
    private func writeToFile() throws {
        let filepath = try NSFileWritingDirectory()
        let header = "/" + config.outputFileName + ".h"
        outputHeaderStack.push("""
            //
            //  \(config.outputFileName).h
            //
            //  This file is auto generated by fit.
            //  Github: https://github.com/k
            //
            //  Copyright © 2018-present Archer. All rights reserved.
            //
            
            #import <UIKit/UIKit.h>\n
            """)
        if config.frameworkType == .YYModel {
            if config.confirmsProtocol == .yes {
                outputHeaderStack += """
                    #import <YYKit/NSObject+YYModel.h>\n
                    NS_ASSUME_NONNULL_BEGIN \n\n
                    """
            } else {
                outputHeaderStack += """
                
                NS_ASSUME_NONNULL_BEGIN \n\n
                """
            }
        } else if config.frameworkType == .MJExtension {
            outputHeaderStack += """
            #import <MJExtension/MJExtension.h>\n
            NS_ASSUME_NONNULL_BEGIN \n\n
            """
        } else {
            outputHeaderStack += """
            
            NS_ASSUME_NONNULL_BEGIN \n\n
            """
        }
        
        outputImplementationStack.push("""
            //
            //  \(config.outputFileName).m
            //
            //  This file is auto generated by fit.
            //  Github: https://github.com/k
            //
            //  Copyright © 2018-present Archer. All rights reserved.
            //
            
            #import "\(config.outputFileName).h"\n\n
            """)
        
        let implementation = "/" + config.outputFileName + ".m"
        try outputHeaderStack.reversed().joined().write(toFile: filepath + header, atomically: true, encoding: .utf8)
        try outputImplementationStack.reversed().joined().write(toFile: filepath + implementation, atomically: true, encoding: .utf8)
    }
}


// MARK: Supporting
fileprivate let NSIntEncodingType = "q"
fileprivate let NSDoubleEncodingType = "d"
internal func NSFileWritingDirectory() throws -> String  {
    let filepath = NSHomeDirectory() + "/Desktop/fit"
    try FileManager.default.createDirectory(atPath: filepath, withIntermediateDirectories: true, attributes: nil)
    return filepath
}