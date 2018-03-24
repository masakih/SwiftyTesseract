//
//  SwiftyTesseract.swift
//  SwiftyTesseract
//
//  Created by Steven Sherry on 2/28/18.
//  Copyright © 2018 Steven Sherry. All rights reserved.
//

import UIKit
import libtesseract
import libleptonica

typealias TessBaseAPI = OpaquePointer
typealias TessString = UnsafePointer<Int8>
typealias Pix = UnsafeMutablePointer<PIX>?

public class SwiftyTesseract {
  
  private let tesseract: TessBaseAPI = TessBaseAPICreate()
  
  /// **Only available for** `EngineMode.tesseractOnly`.
  /// **Setting** `whiteList` **in any other EngineMode will do nothing**.
  ///
  /// Sets a `String` of characters that will **only** be recognized. This does **not** filter values.
  ///
  /// Example: setting a whiteList of "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  /// with an image containing digits may result in "1" being recognized as "I" and "2" being
  /// recognized as "Z". Set this value **only** if it is 100% certain the characters that are
  /// defined will **only** be present during recognition.
  ///
  /// **This may cause unpredictable recognition results if characters not defined in whiteList**
  /// **are present**. If **removal** and not **replacement** is desired, filtering the recognition
  /// string is a better option.
  public var whiteList: String? {
    didSet {
      if let whiteList = whiteList {
        setTesseractVariable(.whiteList, value: whiteList)
      }
    }
  }
  
  /// **Only available for** `EngineMode.tesseractOnly`.
  /// **Setting** `blackList` **in any other EngineMode will do nothing**.
  ///
  /// Sets a `String` of characters that will **not** be recognized. This does **not** filter values.
  ///
  /// Example: setting a blackList of "0123456789" with an image containing digits may result in
  /// "1" being recognized as "I" and "2" being recognized as "Z". Set this value **only** if it
  /// is 100% certain that the characters defined will **not** be present during recognition.
  ///
  /// **This may cause unpredictable recognition results if characters defined in blackList are**
  /// **present**. If **removal** and not **replacement** is desired, filtering the recognition
  /// string is a better option
  public var blackList: String? {
    didSet {
      if let blackList = blackList {
        setTesseractVariable(.blackList, value: blackList)
      }
    }
  }
  
  /// The current version of the underlying Tesseract library
  lazy public private(set) var version: String? = {
    guard let tesseractVersion = TessVersion() else { return nil }
    return String(tesseractString: tesseractVersion)
  }()
  
  /// Creates an instance of SwiftyTesseract. The tessdata folder MUST be
  /// in your Xcode project as a folder reference (blue folder icon, not yellow) and be named
  /// "tessdata"
  ///
  /// - Parameters:
  ///   - languages: Languages of the text to be recognized
  ///   - bundle: The bundle that contains the tessdata folder - default is .main
  ///   - engineMode: The tesseract engine mode - default is .lstmOnly
  public init(languages: [RecognitionLanguage],
              bundle: Bundle = .main,
              engineMode: EngineMode = .lstmOnly) throws {
    
    let stringLanguages = RecognitionLanguage.createLanguageString(from: languages)
    
    // Required for Tesseract to access the .traineddata files
    setenv("TESSDATA_PREFIX", bundle.pathToTrainedData, 1)
    
    // This traps to avoid undefined behavior
    guard TessBaseAPIInit2(tesseract,
                           bundle.pathToTrainedData,
                           stringLanguages,
                           TessOcrEngineMode(rawValue: engineMode.rawValue)) == 0
    else { throw SwiftyTesseractError.initializationError }
    
  }
  
  /// Convenience initializer for creating an instance of SwiftyTesseract with one language to avoid having to
  /// input an array with one value (e.g. [.english]) for the languages parameter
  ///
  /// - Parameters:
  ///   - language: The language of the text to be recognized
  ///   - bundle: The bundle that contains the tessdata folder - default is .main
  ///   - engineMode: The tesseract engine mode - default is .lstmOnly
  public convenience init?(language: RecognitionLanguage,
                          bundle: Bundle = .main,
                          engineMode: EngineMode = .lstmOnly) throws {
    
    try self.init(languages: [language], bundle: bundle, engineMode: engineMode)
  }
  
  deinit {
    // Release the tesseract instance from memory
    TessBaseAPIEnd(tesseract)
    TessBaseAPIDelete(tesseract)
  }
  
  /// Takes a UIImage and passes resulting recognized UTF-8 text into completion handler
  ///
  /// - Parameters:
  ///   - image: The image to perform recognition on
  ///   - completionHandler: The action to be performed on the recognized string
  ///
  public func performOCR(on image: UIImage, completionHandler: @escaping (String?) -> ()) throws {
    
    // pixImage is a var because it has to passed as an inout parameter to pixDestroy to release the memory allocation
    var pixImage = try createPix(from: image)
    TessBaseAPISetImage2(tesseract, pixImage)
    
    if TessBaseAPIGetSourceYResolution(tesseract) < 70 {
      TessBaseAPISetSourceResolution(tesseract, 300)
    }
  
    guard let tesseractString = TessBaseAPIGetUTF8Text(tesseract) else {
      completionHandler(nil)
      return
    }
    
    defer {
      // Release the Pix instance from memory
      pixDestroy(&pixImage)
      // Release the Tesseract string from memory
      TessDeleteText(tesseractString)
    }
    
    let swiftString = String(tesseractString: tesseractString)
    completionHandler(swiftString)
  }
  
  // MARK: - Helper functions
  
  private func createPix(from image: UIImage) throws -> Pix {
    let filename = try save(image: image).path
    return pixRead(filename)
  }
  
  private func save(image: UIImage) throws -> URL {
    guard let data = UIImagePNGRepresentation(image) else { throw SwiftyTesseractError.imageConversionError }
    let url = getDocumentsDirectory().appendingPathComponent("temp.png")
    try data.write(to: url)
    return url
  }
  
  private func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
  }
  
  private func setTesseractVariable(_ variableName: TesseractVariableName, value: String) {
    TessBaseAPISetVariable(tesseract, variableName.rawValue, value)
  }
  
}
