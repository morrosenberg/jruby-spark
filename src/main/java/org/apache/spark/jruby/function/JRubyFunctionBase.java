package org.apache.spark.jruby.function;

import org.apache.spark.jruby.ExecutorBootstrap;
import org.apache.spark.jruby.JRubyIteratableAdaptor;
import org.jruby.*;
import org.jruby.javasupport.JavaUtil;
import org.jruby.runtime.Block;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;

import java.io.ObjectStreamException;
import java.io.Serializable;
import java.util.Iterator;

import static org.apache.spark.jruby.TypeUtils.javaToRuby;
import static org.apache.spark.jruby.TypeUtils.rubyToJava;

/**
 * Created by chenyh on 3/30/16.
 */
public abstract  class JRubyFunctionBase implements Serializable {

    protected byte[] bytecode;
    private transient RubyProc proc;

    public JRubyFunctionBase(byte[] bytecode) {
        this.bytecode = bytecode;
        buildProc();
    }

    /*
    private Object readResolve() throws ObjectStreamException {
        System.err.println("Resolving lambda");
        buildProc();
        return this;
    }*/

    private synchronized void buildProc() {
        // build runtime
        if (proc != null)
            return;
        Ruby runtime = ExecutorBootstrap.getInstance().getRuntime();
        // Ruby.setThreadLocalRuntime(runtime);

        RubyString data = RubyString.newString(runtime, bytecode);
        IRubyObject obj = runtime.getMarshal().callMethod(getCurrentContext(), "load", data);
        if (obj instanceof RubyProc) {
            this.proc = (RubyProc) obj;
        } else if (obj instanceof RubySymbol) {
            RubySymbol sym = (RubySymbol)obj;
            this.proc = (RubyProc)sym.to_proc(getCurrentContext());
        } else {
            throw new RuntimeException("bytecode is not a proc or a symbol");
        }
        System.err.println("Ruby proc: " + proc + ", " + proc.getBlock().getSignature());
    }

    private void ensureProc() {
        if (proc == null)
            buildProc();
    }

    public IRubyObject callProc(IRubyObject [] args, Block blockCallArg) {
        ensureProc();
        return this.proc.call(getCurrentContext(), args, blockCallArg);
    }

    public IRubyObject callProc1NoConvert(Object obj) {
        IRubyObject args[] = new IRubyObject[1];
        Ruby runtime = getRuntime();
        args[0] = javaToRuby(runtime, obj);
        IRubyObject rbObj = callProc(args, Block.NULL_BLOCK);
        return rbObj;//JavaUtil.convertRubyToJava(rbObj);
    }

    public Object callProc1(Object obj) {
        return rubyToJava(getRuntime(), callProc1NoConvert(obj));//JavaUtil.convertRubyToJava(rbObj);
    }

    public Object callProc2(Object obj1, Object obj2) {
        IRubyObject args[] = new IRubyObject[2];
        Ruby runtime = getRuntime();
        args[0] = javaToRuby(runtime, obj1);
        args[1] = javaToRuby(runtime, obj2);
        IRubyObject rbObj = callProc(args, Block.NULL_BLOCK);
        return rubyToJava(getRuntime(), rbObj);//JavaUtil.convertRubyToJava(rbObj);
    }

    public void callProc1NoResult(Object obj) {
        IRubyObject args[] = new IRubyObject[1];
        Ruby runtime = getRuntime();
        args[0] = javaToRuby(runtime, obj);
        callProc(args, Block.NULL_BLOCK);
    }


    public Ruby getRuntime() {
        return ExecutorBootstrap.getInstance().getRuntime();
    }

    public ThreadContext getCurrentContext() {
        // getCurrentContext() will adopt current native thread if needed
        return getRuntime().getCurrentContext();
    }
}
