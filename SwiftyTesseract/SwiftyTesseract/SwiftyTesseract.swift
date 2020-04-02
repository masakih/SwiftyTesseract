//
//  SwiftyTesseract.swift
//  SwiftyTesseract
//
//  Created by Steven Sherry on 2/28/18.
//  Copyright © 2018 Steven Sherry. All rights reserved.
//

import UIKit
import Combine
import libtesseract
import libleptonica

typealias TessBaseAPI = OpaquePointer
typealias Pix = UnsafeMutablePointer<PIX>?

/// A class to perform optical character recognition with the open-source Tesseract library
public class SwiftyTesseract {
  
  // MARK: - Properties
  private let tesseract: TessBaseAPI = TessBaseAPICreate()
    
  private let bundle: Bundle
  
  /// Required to make `performOCR(on:completionHandler:)` thread safe. Runs faster on average than a `DispatchQueue` with `.barrier` flag.
  private let semaphore = DispatchSemaphore(value: 1)

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
      guard let whiteList = whiteList else { return }
      setTesseractVariable(.whiteList, value: whiteList)
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
      guard let blackList = blackList else { return }
      setTesseractVariable(.blackList, value: blackList)
    }
  }
    
  /// Preserve multiple interword spaces
  public var preserveInterwordSpaces: Bool? {
    didSet {
      guard let preserveInterwordSpaces = preserveInterwordSpaces else { return }
      setTesseractVariable(.preserveInterwordSpaces, value: preserveInterwordSpaces ? "1" : "0")
    }
  }
  
  /// Minimum character height
  public var minimumCharacterHeight: Int? {
    didSet {
      guard let minimumCharacterHeight = minimumCharacterHeight else { return }
      setTesseractVariable(.oldCharacterHeight, value: "1")
      setTesseractVariable(.minimumCharacterHeight, value: String(minimumCharacterHeight))
    }
  }
  
  /// The current version of the underlying Tesseract library
  lazy public private(set) var version: String? = {
    guard let tesseractVersion = TessVersion() else { return nil }
    return String(cString: tesseractVersion)
  }()
  
  private init(languageString: String,
               bundle: Bundle = .main,
               engineMode: EngineMode = .lstmOnly) {
    
    // save input bundle
    self.bundle = bundle
    
    setEnvironmentVariable(.tessDataPrefix, value: bundle.pathToTrainedData)
    
    // This variable's value somehow persists between deinit and init, default value should be set
    setTesseractVariable(.oldCharacterHeight, value: "0")
    
    guard TessBaseAPIInit2(tesseract,
                           bundle.pathToTrainedData,
                           languageString,
                           TessOcrEngineMode(rawValue: engineMode.rawValue)) == 0
    else { fatalError(SwiftyTesseract.Error.initializationErrorMessage) }
    
  }
  
  // MARK: - Initialization
  /// Creates an instance of SwiftyTesseract using standard RecognitionLanguages. The tessdata
  /// folder MUST be in your Xcode project as a folder reference (blue folder icon, not yellow)
  /// and be named "tessdata"
  ///
  /// - Parameters:
  ///   - languages: Languages of the text to be recognized
  ///   - bundle: The bundle that contains the tessdata folder - default is .main
  ///   - engineMode: The tesseract engine mode - default is .lstmOnly
  public convenience init(languages: [RecognitionLanguage],
              bundle: Bundle = .main,
              engineMode: EngineMode = .lstmOnly) {
    
    let stringLanguages = RecognitionLanguage.createLanguageString(from: languages)
    self.init(languageString: stringLanguages, bundle: bundle, engineMode: engineMode)
  }
  
  /// Convenience initializer for creating an instance of SwiftyTesseract with one language to avoid having to
  /// input an array with one value (e.g. [.english]) for the languages parameter
  ///
  /// - Parameters:
  ///   - language: The language of the text to be recognized
  ///   - bundle: The bundle that contains the tessdata folder - default is .main
  ///   - engineMode: The tesseract engine mode - default is .lstmOnly
  public convenience init(language: RecognitionLanguage,
                          bundle: Bundle = .main,
                          engineMode: EngineMode = .lstmOnly) {
    
    self.init(languages: [language], bundle: bundle, engineMode: engineMode)
  }
  
  deinit {
    // Releases the tesseract instance from memory
    TessBaseAPIEnd(tesseract)
    TessBaseAPIDelete(tesseract)
  }
  
  // MARK: - Methods
  /// Takes a UIImage and passes resulting recognized UTF-8 text into completion handler
  ///
  /// - Parameters:
  ///   - image: The image to perform recognition on
  ///   - completionHandler: The action to be performed on the recognized string
  ///
  @available(*, deprecated, message: "use performOCR(on:) for synchronous or performOCRPublisher(on:) for asynchronous behavior")
  public func performOCR(on image: UIImage, completionHandler: (String?) -> ()) {
    switch performOCR(on: image) {
      case let .success(string): completionHandler(string)
      case .failure: completionHandler(nil)
    }
  }
  
  
  /// Performs OCR on a `UIImage`
  /// - Parameter image: The image to perform recognition on
  /// - Returns: A result containing the recognized `String `or an `Error` if recognition failed
  public func performOCR(on image: UIImage) -> Result<String, Swift.Error> {
    let _ = semaphore.wait(timeout: .distantFuture)
    defer { semaphore.signal() }
    
    let pixResult = Result { try createPix(from: image) }
    defer { pixResult.destroy() }
    
    return pixResult.flatMap { pix in
      TessBaseAPISetImage2(tesseract, pix)

      if TessBaseAPIGetSourceYResolution(tesseract) < 70 {
        TessBaseAPISetSourceResolution(tesseract, 300)
      }
      
      guard let cString = TessBaseAPIGetUTF8Text(tesseract) else { return .failure(SwiftyTesseract.Error.unableToExtractTextFromImage) }
      defer { TessDeleteText(cString) }
      
      return .success(String(cString: cString) )
    }
  }
  
  /// Creates a *cold* publisher that performs OCR on a provided image upon subscription
  /// - Parameter image: The image to perform recognition on
  /// - Returns: A cold publisher that emits a single `String` on success or an `Error` on failure.
  @available(iOS 13.0, *)
  public func performOCRPublisher(on image: UIImage) -> AnyPublisher<String, Swift.Error> {
    Deferred {
      Future { [weak self] promise in
        promise(self?.performOCR(on: image) ?? .failure(SwiftyTesseract.Error.imageConversionError))
      }
    }
    .eraseToAnyPublisher()
  }
  
  /// Takes an array UIImages and returns the PDF as a `Data` object.
  /// If using PDFKit introduced in iOS 11, this will produce a valid
  /// PDF Document.
  ///
  /// - Parameter images: Array of UIImages to perform OCR on
  /// - Returns: PDF `Data` object
  /// - Throws: SwiftyTesseractError
  public func createPDF(from images: [UIImage]) throws -> Data {
    let _ = semaphore.wait(timeout: .distantFuture)
    defer {
      semaphore.signal()
    }
    
    // create unique file path
    let filepath = try processPDF(images: images)
    
    // get data from pdf and remove file
    let data = try Data(contentsOf: filepath)
    try FileManager.default.removeItem(at: filepath)
    
    return data
  }
  
  // MARK: - Helper functions

  private func createPix(from image: UIImage) throws -> Pix {
    guard let data = image.pngData() else { throw SwiftyTesseract.Error.imageConversionError }
    let rawPointer = (data as NSData).bytes
    let uint8Pointer = rawPointer.assumingMemoryBound(to: UInt8.self)
    return pixReadMem(uint8Pointer, data.count)
  }
  
  private func setTesseractVariable(_ variableName: TesseractVariableName, value: String) {
    TessBaseAPISetVariable(tesseract, variableName.rawValue, value)
  }

  private func setEnvironmentVariable(_ variableName: TesseractVariableName, value: String) {
    setenv(variableName.rawValue, value, 1)
  }
  
  private func processPDF(images: [UIImage]) throws -> URL {
    let filepath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    
    let renderer = try makeRenderer(at: filepath)
    
    defer {
      TessDeleteResultRenderer(renderer)
    }
    
    try render(images, with: renderer)
    
    return filepath.appendingPathExtension("pdf")
  }
  
  private func render(_ images: [UIImage], with renderer: OpaquePointer) throws {
    let pixImages = try images.map(createPix)
    
    defer {
      for var pix in pixImages { pixDestroy(&pix) }
    }
    
    try pixImages.enumerated().forEach { [weak self] pageNumber, pix in
      guard let self = self else { return }
      guard TessBaseAPIProcessPage(self.tesseract, pix, Int32(pageNumber), "page.\(pageNumber)", nil, 30000, renderer) == 1 else {
        throw SwiftyTesseract.Error.unableToProcessPage
      }
    }
    
    guard TessResultRendererEndDocument(renderer) == 1 else { throw SwiftyTesseract.Error.unableToEndDocument }
  }
  
  private func makeRenderer(at url: URL) throws -> OpaquePointer {
    guard let renderer = TessPDFRendererCreate(url.path, bundle.pathToTrainedData, 0) else {
      throw SwiftyTesseract.Error.unableToCreateRenderer
    }
    
    guard TessResultRendererBeginDocument(renderer, "Unkown Title") == 1 else {
      TessDeleteResultRenderer(renderer)
      throw SwiftyTesseract.Error.unableToBeginDocument
    }
    
    return renderer
  }
}

private extension Result where Success == Pix {
  func destroy() {
    guard case var .success(pix) = self else { return }
    pixDestroy(&pix)
  }
}
