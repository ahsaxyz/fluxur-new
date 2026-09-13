"use client";

import Link from "next/link";
import { CheckCircle, Home, Plus, Search } from "lucide-react";
import BinaryRain from "@/components/BinaryRain";

export default function CreateSuccessPage() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white relative overflow-hidden">
      {/* Binary Rain Background */}
      <BinaryRain />

      {/* Gradient overlays */}
      <div className="absolute inset-0 bg-gradient-to-b from-[#0a0a0a]/70 via-[#0a0a0a]/50 to-[#0a0a0a]/90 pointer-events-none z-[1]" />

      {/* Content */}
      <main className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4">
        <div className="max-w-md w-full text-center">
          {/* Success Icon */}
          <div className="mb-8">
            <div className="w-24 h-24 mx-auto rounded-full bg-green-500/20 flex items-center justify-center mb-6 animate-pulse">
              <CheckCircle className="w-12 h-12 text-green-400" />
            </div>
            <h1 className="text-3xl sm:text-4xl font-bold neon-text mb-4">
              Commitment Created!
            </h1>
            <p className="text-gray-400 text-lg">
              Your commitment has been successfully created and is now live on the platform.
            </p>
          </div>

          {/* Info Card */}
          <div className="neon-box rounded-2xl p-6 mb-8 text-left">
            <h2 className="text-white font-semibold mb-3">What happens next?</h2>
            <ul className="space-y-3 text-gray-400 text-sm">
              <li className="flex items-start gap-3">
                <span className="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-cyan-400 text-xs">1</span>
                </span>
                Your commitment is now visible on the Discover page
              </li>
              <li className="flex items-start gap-3">
                <span className="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-cyan-400 text-xs">2</span>
                </span>
                Token holders can view and vote on your milestones
              </li>
              <li className="flex items-start gap-3">
                <span className="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-cyan-400 text-xs">3</span>
                </span>
                Complete milestones to unlock escrowed funds
              </li>
            </ul>
          </div>

          {/* Action Buttons */}
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link
              href="/"
              className="neon-btn rounded-full px-8 py-3 text-base font-semibold flex items-center justify-center gap-2"
            >
              <Home className="w-5 h-5" />
              Back to Home
            </Link>
            <Link
              href="/discover"
              className="neon-btn-secondary rounded-full px-8 py-3 text-base font-semibold flex items-center justify-center gap-2"
            >
              <Search className="w-5 h-5" />
              View on Discover
            </Link>
          </div>

          {/* Create Another */}
          <div className="mt-6">
            <Link
              href="/create"
              className="text-gray-500 hover:text-cyan-400 text-sm flex items-center justify-center gap-2 transition-colors"
            >
              <Plus className="w-4 h-4" />
              Create another commitment
            </Link>
          </div>
        </div>
      </main>
    </div>
  );
}
