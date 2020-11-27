import Foundation

public protocol SMCrashDelegate: NSObjectProtocol {
    func crashHandlerDidCatchCrash(with info: SMCrashInfo)
}

public enum SMCrashType: String {
    case signal, exception
}

public class SMCrashInfo {
    
    public let date: TimeInterval
    public let type: SMCrashType
    public let name: String
    public let reason: String
    public let callStack: [String]
    
    public init(date: TimeInterval, type:SMCrashType, name:String, reason:String, callStack:[String]) {
        self.date = date
        self.type = type
        self.name = name
        self.reason = reason
        self.callStack = callStack
    }
}

public class SMCrashHandler {
    
    public private(set) static var isActive: Bool = false
    
    public static func add(delegate: SMCrashDelegate) {
        // delete null week delegate and delegate from parameter
        self.delegates = self.delegates.filter {
            return $0.delegate != nil && $0.delegate?.hash != delegate.hash
        }
        
        // Append delegate with weak wrapped
        self.delegates.append(WeakCrashDelegate(delegate: delegate))

        self.open()
    }
    
    public static func remove(delegate: SMCrashDelegate) {
        self.delegates = self.delegates.filter {
            return $0.delegate != nil && $0.delegate?.hash != delegate.hash
        }
        
        if self.delegates.count == 0 {
            self.close()
        }
    }
    
    // MARK: - Private functions

    private static func open() {
        guard self.isActive == false else {
            return
        }
        Self.isActive = true
        
        app_old_exceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(Self.RecieveException)
        self.setCrashSignalHandler()
    }
    
    private static func close() {
        guard self.isActive == true else {
            return
        }
        Self.isActive = false
        NSSetUncaughtExceptionHandler(app_old_exceptionHandler)
    }
    
    private static func setCrashSignalHandler(){
        signal(SIGABRT, Self.RecieveSignal)
        signal(SIGILL, Self.RecieveSignal)
        signal(SIGSEGV, Self.RecieveSignal)
        signal(SIGFPE, Self.RecieveSignal)
        signal(SIGBUS, Self.RecieveSignal)
        signal(SIGPIPE, Self.RecieveSignal)
        //http://stackoverflow.com/questions/36325140/how-to-catch-a-swift-crash-and-do-some-logging
        signal(SIGTRAP, Self.RecieveSignal)
    }
    
    private static let RecieveException: @convention(c) (NSException) -> Swift.Void = { (exception) -> Void in
        if let oldExceptionHandler = app_old_exceptionHandler {
            oldExceptionHandler(exception)
        }
        
        guard SMCrashHandler.isActive == true else {
            return
        }
        
        let reason = exception.reason ?? ""
        let name = exception.name
        
        
        let info = SMCrashInfo(date: Date().timeIntervalSince1970, type: .exception, name: name.rawValue, reason: reason, callStack: exception.callStackSymbols)
        for delegate in SMCrashHandler.delegates {
            delegate.delegate?.crashHandlerDidCatchCrash(with: info)
        }
    }
    
    private static let RecieveSignal : @convention(c) (Int32) -> Void = { (signal) -> Void in
        guard SMCrashHandler.isActive == true else {
            return
        }
        
        var stack = Thread.callStackSymbols
        stack.removeFirst(2)
        let reason = "Signal \(SMCrashHandler.name(of: signal))(\(signal)) was raised.\n"
        
        let info = SMCrashInfo(date: Date().timeIntervalSince1970, type: .signal, name: SMCrashHandler.name(of: signal), reason: reason, callStack: stack)
        for delegate in SMCrashHandler.delegates {
            delegate.delegate?.crashHandlerDidCatchCrash(with: info)
        }
        SMCrashHandler.killApp()
    }
    
    private static func name(of signal:Int32) -> String {
        switch (signal) {
        case SIGABRT:
            return "SIGABRT"
        case SIGILL:
            return "SIGILL"
        case SIGSEGV:
            return "SIGSEGV"
        case SIGFPE:
            return "SIGFPE"
        case SIGBUS:
            return "SIGBUS"
        case SIGPIPE:
            return "SIGPIPE"
        default:
            return "OTHER"
        }
    }
    
    private static func killApp(){
        NSSetUncaughtExceptionHandler(nil)
        
        signal(SIGABRT, SIG_DFL)
        signal(SIGILL, SIG_DFL)
        signal(SIGSEGV, SIG_DFL)
        signal(SIGFPE, SIG_DFL)
        signal(SIGBUS, SIG_DFL)
        signal(SIGPIPE, SIG_DFL)
        
        kill(getpid(), SIGKILL)
    }
    
    fileprivate static var delegates = [WeakCrashDelegate]()
}

fileprivate class WeakCrashDelegate {
    weak var delegate: SMCrashDelegate?
    
    init(delegate: SMCrashDelegate) {
        self.delegate = delegate
    }
}

fileprivate var app_old_exceptionHandler:(@convention(c) (NSException) -> Swift.Void)? = nil
